import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/storage/local_db.dart';
import 'package:the_vault/src/core/sync/sync_engine.dart';

/// A sync engine talking to a fake server that answers every request with [answer].
class Rig {
  Rig() {
    engine = SyncEngine(
      db: db,
      api: ApiClient(
        base: Uri.parse('https://vault.example.ts.net'),
        token: 'tok',
        client: MockClient((r) async {
          requests++;
          // Slow enough for other sync requests to arrive meanwhile.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return answer(r);
        }),
      ),
      blobs: BlobFiles(dir.path),
      onConflict: (_, _, _) async => false,
      onRevoked: () async => revoked++,
      onUnrecognized: () async => unrecognized++,
    );
  }

  final db = LocalDb.memory();
  final dir = Directory.systemTemp.createTempSync('tv-sync');
  late final SyncEngine engine;
  http.Response Function(http.Request r) answer = (_) => http.Response('', 500);
  int requests = 0;
  int revoked = 0;
  int unrecognized = 0;

  Future<void> close() async {
    await engine.dispose();
    db.close();
    dir.deleteSync(recursive: true);
  }
}

/// An error of The Vault.
http.Response error(int status, String code, {String version = '1.2.0'}) => http.Response(
      jsonEncode({'error': {'code': code, 'message': code}}),
      status,
      headers: {'content-type': 'application/json', 'x-thevault-server': version},
    );

/// A server that accepts everything.
http.Response working(http.Request r) => switch (r.url.path) {
      '/v1/records' when r.method == 'GET' => http.Response(jsonEncode({'records': [], 'latest': 0, 'more': false}), 200),
      _ when r.method == 'PUT' => http.Response(jsonEncode({'rev': 1}), 200),
      _ => http.Response('', 404),
    };

void main() {
  late Rig rig;
  setUp(() {
    rig = Rig();
    // Local edits not sent yet: they must survive whatever the server says (unless it revoked the device).
    rig.db.putPending(id: 'a', op: 'put', data: Uint8List.fromList([1, 2, 3]));
  });
  tearDown(() async {
    SyncEngine.unrecognizedRetry = const Duration(minutes: 10);
    await rig.close();
  });

  test('401 device_unknown: nothing is wiped, the user is told once, the server is not asked at every change', () async {
    rig.answer = (_) => error(401, 'device_unknown');
    await rig.engine.sync();
    expect(rig.revoked, 0, reason: 'an unknown token is not a revocation');
    expect(rig.unrecognized, 1);
    expect(rig.engine.unrecognized, isTrue);
    expect(rig.engine.state.value, SyncState.error);
    expect(rig.db.pendingCount, 1, reason: 'local edits are kept');

    final asked = rig.requests;
    await rig.engine.sync();
    await rig.engine.sync();
    expect(rig.requests, asked, reason: 'syncs wait before asking again');

    await rig.engine.sync(force: true);
    expect(rig.requests, greaterThan(asked), reason: 'a forced sync asks anyway');
    expect(rig.unrecognized, 1, reason: 'the notice is not repeated at every retry');
    expect(rig.revoked, 0);

    // The server knows this device again (e.g. its data came back): everything resumes.
    rig.answer = working;
    await rig.engine.sync(force: true);
    expect(rig.engine.unrecognized, isFalse);
    expect(rig.engine.state.value, SyncState.idle);
    expect(rig.db.pendingCount, 0);

    // A new 401 later is a new problem: told again.
    rig.db.putPending(id: 'b', op: 'put', data: Uint8List.fromList([4]));
    rig.answer = (_) => error(401, 'device_unknown');
    await rig.engine.sync();
    expect(rig.unrecognized, 2);
    expect(rig.revoked, 0);
  });

  test('after a 401 it asks again by itself, and resumes once the server knows the device again', () async {
    SyncEngine.unrecognizedRetry = const Duration(milliseconds: 150);
    rig.answer = (_) => error(401, 'device_unknown');
    await rig.engine.sync();
    expect(rig.engine.unrecognized, isTrue);
    rig.answer = working;
    // Nobody calls sync(): the engine's own retry pushes the pending edit.
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (rig.engine.unrecognized) {
      if (DateTime.now().isAfter(end)) fail('no retry');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(rig.db.pendingCount, 0);
    expect(rig.unrecognized, 1);
  });

  test('recognized() ends the pause right away (e.g. the real-time channel connected)', () async {
    rig.answer = (_) => error(401, 'device_unknown');
    await rig.engine.sync();
    final asked = rig.requests;
    rig.answer = working;
    rig.engine.recognized();
    expect(rig.engine.unrecognized, isFalse);
    await rig.engine.sync();
    expect(rig.requests, greaterThan(asked));
    expect(rig.db.pendingCount, 0);
  });

  test('401 device_revoked: revoked, once, and the engine stops', () async {
    rig.answer = (_) => error(401, 'device_revoked');
    // Several requests at once (start, real-time 'refused', fallback timer…).
    await Future.wait([rig.engine.sync(), rig.engine.sync(), rig.engine.sync()]);
    expect(rig.revoked, 1);
    expect(rig.unrecognized, 0);
    expect(rig.engine.state.value, SyncState.error);
    final asked = rig.requests;
    await rig.engine.sync(force: true);
    expect(rig.requests, asked, reason: 'nothing more is asked after a revocation');
    expect(rig.revoked, 1);
  });

  test('a server up to 1.1.0 answers 401 unauthorized also to a revoked device: wiped, as apps up to 1.1.0 did', () async {
    rig.answer = (_) => error(401, 'unauthorized', version: '1.1.0');
    await rig.engine.sync();
    expect(rig.revoked, 1);
    expect(rig.unrecognized, 0);
  });

  test('the server version never decides: a pre-tag build reporting 1.1.0-… does not wipe unknown devices', () async {
    rig.answer = (_) => error(401, 'device_unknown', version: '1.1.0-3-g638711f');
    await rig.engine.sync();
    expect(rig.revoked, 0);
    expect(rig.unrecognized, 1);
  });

  test('other refusals neither wipe nor warn, and do not pause syncing', () async {
    for (final r in [
      http.Response('<html>Authorization Required</html>', 401), // a proxy, not The Vault
      http.Response('', 401),
      error(403, 'forbidden'),
      http.Response('<html>Forbidden</html>', 403),
      error(500, 'internal'),
    ]) {
      rig.answer = (_) => r;
      final asked = rig.requests;
      await rig.engine.sync();
      expect(rig.requests, greaterThan(asked), reason: '${r.statusCode} ${r.body}');
      expect(rig.engine.state.value, SyncState.error);
      expect(rig.engine.unrecognized, isFalse);
    }
    rig.answer = (_) => http.Response('', 502); // Tailscale Funnel with the server stopped
    await rig.engine.sync();
    expect(rig.engine.state.value, SyncState.offline);
    expect(rig.revoked, 0);
    expect(rig.unrecognized, 0);
    expect(rig.db.pendingCount, 1);
  });
}
