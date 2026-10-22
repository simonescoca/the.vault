// The new device's side of the approval against a fake server, honest or not (docs/SECURITY.md §7).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:the_vault/src/core/account/account_service.dart';
import 'package:the_vault/src/core/account/identity.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';

const approvalId = 'ap1';
const userId = 'u1';

/// Plays the server and the approving device. Each GET of the approval returns what [view] says.
class FakeServer {
  FakeServer(this.crypto) : vaultKey = crypto.newVaultKey() {
    approver = crypto.newBoxKeyPair();
    approverNonce = crypto.randomBytes(32);
  }

  final VaultCrypto crypto;
  final SecureKey vaultKey;
  late final KeyPair approver;
  late final Uint8List approverNonce;
  late Uint8List newDeviceKey;

  String state = 'pending';
  Uint8List? revealed;
  bool sendKeyCheck = true;
  final calls = <String>[];

  /// Overrides the approval sent to the new device (to tamper with it).
  Map<String, dynamic> Function(Map<String, dynamic> honest)? tamper;

  Map<String, dynamic> get honest => {
        'id': approvalId,
        'state': state,
        if (state != 'pending') ...{'responderPublicKey': b64(approver.publicKey), 'responderNonce': b64(approverNonce)},
        if (revealed != null) 'revealedNonce': b64(revealed!),
      };

  /// The approving device approves: the vault key sealed for the new device with [by] (default: the approver's key).
  void approve({KeyPair? by}) {
    final sealed = crypto.sealVaultKey(
      vaultKey: vaultKey,
      userId: userId,
      approvalId: approvalId,
      newDevicePublicKey: newDeviceKey,
      approverSecretKey: (by ?? approver).secretKey,
    );
    state = 'approved';
    final prev = tamper;
    tamper = (j) => {...(prev?.call(j) ?? j), 'box': b64(sealed.box), 'boxNonce': b64(sealed.nonce)};
  }

  String expectedCode() => crypto.approvalCode(
        approvalId: approvalId,
        newDevicePublicKey: newDeviceKey,
        approverPublicKey: approver.publicKey,
        approverNonce: approverNonce,
        newDeviceNonce: revealed!,
      );

  http.Response _json(Object j) => http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    final call = '${r.method} ${r.url.path}';
    calls.add(call);
    switch (call) {
      case 'POST /v1/approvals':
        return _json({'approvalId': approvalId});
      case 'GET /v1/approvals/$approvalId':
        return _json(tamper?.call(honest) ?? honest);
      case 'POST /v1/approvals/$approvalId/reveal':
        revealed = unb64((jsonDecode(r.body) as Map)['nonce'] as String);
        state = 'revealed';
        return http.Response('', 204);
      case 'DELETE /v1/approvals/$approvalId':
        if (state == 'approved') return http.Response(jsonEncode({'error': {'code': 'forbidden', 'message': ''}}), 403);
        state = 'cancelled';
        return http.Response('', 204);
      case 'DELETE /v1/devices/self':
        return http.Response('', 204);
      case 'GET /v1/me':
        return _json({
          'userId': userId,
          'vault': {'initialized': true, 'keyCheck': sendKeyCheck ? b64(crypto.keyCheck(vaultKey)) : null},
        });
    }
    return http.Response(jsonEncode({'error': {'code': 'not_found', 'message': call}}), 404);
  }
}

class Rig {
  Rig(this.crypto) : server = FakeServer(crypto) {
    final kp = crypto.newBoxKeyPair();
    server.newDeviceKey = kp.publicKey;
    identity = Identity(
      server: Uri.parse('https://vault.example.ts.net'),
      email: 'me@example.com',
      userId: userId,
      deviceId: 'd2',
      deviceName: 'PC',
      platform: 'windows',
      token: 'tok',
      devicePublicKey: kp.publicKey,
      deviceSecretKey: kp.secretKey.extractBytes(),
      status: 'pending',
    );
    account = AccountService(crypto: crypto, secrets: secrets, httpClient: MockClient(server.handle));
  }

  final VaultCrypto crypto;
  final FakeServer server;
  final secrets = MemorySecretStore();
  late final Identity identity;
  late final AccountService account;
  final progress = <ApprovalProgress>[];
  late ApprovalRequest request;

  ApprovalRequest start() {
    request = account.requestApproval(identity);
    request.progress.listen(progress.add);
    return request;
  }

  String? get code => progress.whereType<ApprovalCode>().firstOrNull?.code;
  String? get ended => progress.whereType<ApprovalEnded>().firstOrNull?.state;
  bool get granted => progress.any((p) => p is ApprovalGranted);

  /// Waits until [cond] or fails.
  Future<void> until(bool Function() cond, String what) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('timeout waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// A few more polls (to show that nothing happens).
  Future<void> polls([int n = 5]) => Future<void>.delayed(ApprovalRequest.pollEvery * n);

  Future<void> expectNothingSaved() async {
    expect(await secrets.readVaultKey(), isNull);
    expect(granted, isFalse);
    expect(identity.status, 'pending');
  }
}

void main() {
  late VaultCrypto crypto;
  setUpAll(() async {
    crypto = await VaultCrypto.init();
    ApprovalRequest.pollEvery = const Duration(milliseconds: 10);
  });

  test('honest server: approved first, saved only once the user confirms the code', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    expect(r.code, r.server.expectedCode(), reason: 'same code as on the approving device');

    r.server.approve();
    await r.polls();
    await r.expectNothingSaved();

    await r.request.confirmCode();
    await r.until(() => r.granted, 'granted');
    expect(await r.secrets.readVaultKey(), r.server.vaultKey.extractBytes());
    expect(r.identity.status, 'active');
    expect((await r.secrets.readIdentity())!.status, 'active');
  });

  test('honest server: confirmed first, saved when the other device approves', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    await r.request.confirmCode();
    await r.polls();
    await r.expectNothingSaved();

    r.server.approve();
    await r.until(() => r.granted, 'granted');
    expect(await r.secrets.readVaultKey(), r.server.vaultKey.extractBytes());
  });

  test('approved without the code ever shown here → invalid', () async {
    final r = Rig(crypto)..start();
    await r.polls(2);
    r.server.approve(); // straight to approved, no reveal by this device
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'invalid');
    expect(r.code, isNull);
    await r.expectNothingSaved();
    expect(r.server.calls, isNot(contains('POST /v1/approvals/$approvalId/reveal')));
    expect(r.server.calls, contains('DELETE /v1/devices/self'), reason: 'the server says this device is linked: unlink it');
    expect(r.progress.whereType<ApprovalEnded>().single.signedOut, isTrue);
  });

  test('approval with another key than the one the code covers → invalid', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    await r.request.confirmCode();
    // The server swaps in its own key after the code was shown, and seals the vault key with it.
    final intruder = crypto.newBoxKeyPair();
    r.server.tamper = (j) => {...j, 'responderPublicKey': b64(intruder.publicKey)};
    r.server.approve(by: intruder);
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'invalid');
    await r.expectNothingSaved();
  });

  test('a box that does not open with the pinned key → invalid', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    await r.request.confirmCode();
    r.server.approve(by: crypto.newBoxKeyPair()); // same public key announced, sealed by someone else
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'invalid');
    await r.expectNothingSaved();
  });

  test('key or nonce changed between "responded" and "revealed" → invalid', () async {
    final r = Rig(crypto);
    // The reveal reaches the server but its answer is lost; then the server changes the nonce.
    var first = true;
    final inner = r.server.handle;
    final account = AccountService(
      crypto: crypto,
      secrets: r.secrets,
      httpClient: MockClient((req) async {
        final resp = await inner(req);
        if (req.url.path.endsWith('/reveal') && first) {
          first = false;
          r.server.tamper = (j) => {...j, 'responderNonce': b64(crypto.randomBytes(32))};
          throw http.ClientException('connection reset');
        }
        return resp;
      }),
    );
    final request = account.requestApproval(r.identity);
    request.progress.listen(r.progress.add);
    r.server.state = 'responded';
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'invalid');
    expect(r.code, isNull, reason: 'no code computed from values chosen after our nonce was known');
  });

  test('vault without a key check → invalid', () async {
    final r = Rig(crypto)..start();
    r.server.sendKeyCheck = false;
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    await r.request.confirmCode();
    r.server.approve();
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'invalid');
    await r.expectNothingSaved();
  });

  test('"It doesn\'t match" cancels the request on the server', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    await r.request.rejectCode();
    await r.until(() => r.ended != null, 'end');
    expect(r.server.calls, contains('DELETE /v1/approvals/$approvalId'));
    expect(r.server.calls, isNot(contains('DELETE /v1/devices/self')));
    final end = r.progress.whereType<ApprovalEnded>().single;
    expect(end.state, 'mismatch');
    expect(end.signedOut, isFalse, reason: 'still pending: a new request can be made');
    r.server.approve(); // too late
    await r.polls();
    await r.expectNothingSaved();
  });

  test('"It doesn\'t match" after the other device approved: nothing saved, this device is unlinked', () async {
    final r = Rig(crypto)..start();
    r.server.state = 'responded';
    await r.until(() => r.code != null, 'code');
    r.server.approve();
    await r.polls();
    await r.request.rejectCode();
    await r.until(() => r.ended != null, 'end');
    final end = r.progress.whereType<ApprovalEnded>().single;
    expect(end.state, 'mismatch');
    expect(end.signedOut, isTrue);
    expect(r.server.calls, contains('DELETE /v1/devices/self'));
    await r.expectNothingSaved();
    expect(await r.secrets.readIdentity(), isNull);
  });

  test('a revoked device (401 device_revoked) ends like a cancelled request, to start again from the email', () async {
    final r = Rig(crypto);
    final account = AccountService(
      crypto: crypto,
      secrets: r.secrets,
      httpClient: MockClient((req) async => req.method == 'GET'
          ? http.Response(jsonEncode({'error': {'code': 'device_revoked', 'message': ''}}), 401)
          : r.server.handle(req)),
    );
    account.requestApproval(r.identity).progress.listen(r.progress.add);
    await r.until(() => r.ended != null, 'end');
    expect(r.ended, 'cancelled');
    expect(r.progress.whereType<ApprovalEnded>().single.signedOut, isTrue);
  });

  group('the request cannot even start', () {
    Future<ApprovalEnded> startWith(Rig r, http.Response answer) async {
      final account = AccountService(
        crypto: crypto,
        secrets: r.secrets,
        httpClient: MockClient((req) async => req.method == 'POST' && req.url.path == '/v1/approvals' ? answer : r.server.handle(req)),
      );
      account.requestApproval(r.identity).progress.listen(r.progress.add);
      await r.until(() => r.ended != null, 'end');
      return r.progress.whereType<ApprovalEnded>().single;
    }

    http.Response err(int status, String code) => http.Response(jsonEncode({'error': {'code': code, 'message': code}}), status);

    test('unknown or revoked device: start again from the email (no endless Retry)', () async {
      for (final answer in [err(401, 'unauthorized'), err(401, 'device_revoked')]) {
        final r = Rig(crypto);
        final end = await startWith(r, answer);
        expect((end.state, end.signedOut), ('cancelled', true), reason: answer.body);
      }
    });

    test('no longer pending (approved earlier without the key here): signed out', () async {
      final r = Rig(crypto);
      final end = await startWith(r, err(403, 'forbidden'));
      expect((end.state, end.signedOut), ('cancelled', true));
      expect(r.server.calls, contains('DELETE /v1/devices/self'));
      expect(await r.secrets.readIdentity(), isNull);
    });

    test('other errors are reported as they are', () async {
      final r = Rig(crypto);
      final end = await startWith(r, err(500, 'internal'));
      expect((end.state, end.signedOut), ('error', false));
      expect(end.error, isA<ApiException>().having((e) => e.code, 'code', 'internal'));
    });
  });

  group('"I don\'t have other devices" (cancel)', () {
    test('while waiting: the request is cancelled on the server', () async {
      final r = Rig(crypto)..start();
      r.server.state = 'responded';
      await r.until(() => r.code != null, 'code');
      final c = await r.request.cancel();
      expect((c.cancelled, c.signedOut), (true, false));
      expect(r.server.calls, contains('DELETE /v1/approvals/$approvalId'));
      expect(r.server.calls, isNot(contains('DELETE /v1/devices/self')));
    });

    test('after the other device approved: this device is signed out, nothing saved', () async {
      final r = Rig(crypto)..start();
      r.server.state = 'responded';
      await r.until(() => r.code != null, 'code');
      r.server.approve();
      await r.polls();
      final c = await r.request.cancel();
      expect((c.cancelled, c.signedOut), (true, true));
      expect(r.server.calls, contains('DELETE /v1/devices/self'));
      await r.expectNothingSaved();
      expect(await r.secrets.readIdentity(), isNull);
    });

    test('while the key is being saved: not cancelled, the grant goes on', () async {
      final r = Rig(crypto)..start();
      r.server.state = 'responded';
      await r.until(() => r.code != null, 'code');
      r.server.approve();
      await r.until(() => r.server.calls.contains('GET /v1/me'), 'key opened and checked');
      await r.polls(2);
      final confirming = r.request.confirmCode();
      final c = await r.request.cancel();
      await confirming;
      expect(c.cancelled, isFalse);
      await r.until(() => r.granted, 'granted');
      expect(await r.secrets.readVaultKey(), r.server.vaultKey.extractBytes());
    });

    test('after it ended: reports how', () async {
      final r = Rig(crypto)..start();
      r.server.state = 'expired';
      await r.until(() => r.ended != null, 'end');
      final c = await r.request.cancel();
      expect((c.cancelled, c.signedOut), (true, false));
    });
  });
}
