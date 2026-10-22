import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_vault/src/core/api/api_client.dart';

/// A client whose server always answers [status] with [body].
ApiClient answering(int status, String body, {Map<String, String> headers = const {}}) => ApiClient(
      base: Uri.parse('https://vault.example.ts.net'),
      token: 'tok',
      client: MockClient((_) async => http.Response(body, status, headers: headers)),
    );

final isNetwork = isA<NetworkException>();
TypeMatcher<ApiException> isApi(int status, String code) =>
    isA<ApiException>().having((e) => e.status, 'status', status).having((e) => e.code, 'code', code);

void main() {
  group('answers that do not come from the server', () {
    test('502 with an empty body (Tailscale Funnel, server stopped) → unreachable', () async {
      await expectLater(answering(502, '').health(), throwsA(isNetwork));
      await expectLater(answering(502, '').records(0), throwsA(isNetwork));
    });

    test('503 with an HTML page (a proxy) → unreachable', () async {
      await expectLater(answering(503, '<html><body>Service Unavailable</body></html>').health(), throwsA(isNetwork));
    });

    test('504 and other 5xx that are not errors of The Vault → unreachable', () async {
      await expectLater(answering(504, 'upstream timed out').me(), throwsA(isNetwork));
      await expectLater(answering(500, 'Internal Server Error').me(), throwsA(isNetwork));
      await expectLater(answering(502, '{"message":"bad gateway"}').me(), throwsA(isNetwork));
    });

    test('errors of The Vault keep their code, 5xx included', () async {
      await expectLater(answering(500, '{"error":{"code":"internal","message":"internal error"}}').me(), throwsA(isApi(500, 'internal')));
      await expectLater(
          answering(503, '{"error":{"code":"mail_failed","message":"the server could not send the email"}}').requestCode('me@example.com'),
          throwsA(isApi(503, 'mail_failed')));
      await expectLater(
          answering(401, '{"error":{"code":"device_revoked","message":"this device was disconnected"}}').records(0),
          throwsA(isApi(401, 'device_revoked')));
      await expectLater(answering(401, '{"error":{"code":"device_unknown","message":"unknown device"}}').records(0), throwsA(isApi(401, 'device_unknown')));
    });

    test('a 4xx that is not JSON is a bad response, not a revocation', () async {
      await expectLater(answering(403, '<html>Forbidden</html>').records(0), throwsA(isApi(403, 'bad_response')));
      await expectLater(
          answering(401, '<html>Authorization Required</html>').records(0),
          throwsA(isApi(401, 'bad_response').having((e) => e.deviceRevoked, 'revoked', false).having((e) => e.deviceUnknown, 'unknown', false)));
    });

    test('something that is not The Vault on /v1/health', () async {
      // A web page answering 200: "this is not a The Vault server".
      await expectLater(answering(200, '<!doctype html><title>Welcome to nginx</title>').health(), throwsA(isApi(200, 'bad_response')));
      // JSON, but not ours.
      await expectLater(answering(200, '{"status":"ok"}').health(), throwsA(isApi(200, 'not_thevault')));
      expect((await answering(200, '{"service":"thevault","version":"1.1.0"}').health())['version'], '1.1.0');
    });
  });

  group('revoked or unknown device', () {
    Future<ApiException> refused(String code, {int status = 401, Map<String, String> headers = const {}}) async {
      final body = jsonEncode({'error': {'code': code, 'message': code}});
      try {
        await answering(status, body, headers: headers).records(0);
      } on ApiException catch (e) {
        return e;
      }
      fail('no error');
    }

    test('decided by the code of The Vault, never by the server version', () async {
      final revoked = await refused('device_revoked');
      expect((revoked.deviceRevoked, revoked.deviceUnknown), (true, false));
      // A server built from a branch before its tag reports e.g. "1.1.0-3-g638711f": it must not matter.
      for (final v in ['1.1.0-3-g638711f', '1.1.0', '1.2.0', 'dev']) {
        final unknown = await refused('device_unknown', headers: {'x-thevault-server': v});
        expect((unknown.deviceRevoked, unknown.deviceUnknown), (false, true), reason: 'server $v');
      }
      final forbidden = await refused('forbidden', status: 403);
      expect((forbidden.deviceRevoked, forbidden.deviceUnknown), (false, false));
      final revoked403 = await refused('device_revoked', status: 403);
      expect(revoked403.deviceRevoked, isFalse, reason: 'only a 401');
    });

    test('servers up to 1.1.0 answer 401 unauthorized to revoked devices too: the old rule (wipe) stays', () async {
      final e = await refused('unauthorized');
      expect((e.deviceRevoked, e.deviceUnknown), (true, false));
    });

    test('a successful answer with the token says the server knows this device', () async {
      var authorized = 0;
      final ok = answering(200, '{"records":[],"latest":0,"more":false}')..onAuthorized = () => authorized++;
      await ok.records(0);
      expect(authorized, 1);
      final ko = answering(401, '{"error":{"code":"device_unknown","message":""}}')..onAuthorized = () => authorized++;
      await expectLater(ko.records(0), throwsA(isA<ApiException>()));
      expect(authorized, 1);
    });
  });

  group('connection failures → NetworkException', () {
    ApiClient failing(Object error) => ApiClient(base: Uri.parse('https://vault.example.ts.net'), client: MockClient((_) async => throw error));

    for (final (name, error) in [
      ('socket', const SocketException('connection refused')),
      ('TLS handshake', const HandshakeException('certificate verify failed')),
      ('TLS', const TlsException('bad record')),
      ('HTTP', const HttpException('connection closed before full header was received')),
      ('client', http.ClientException('Connection reset by peer')),
    ]) {
      test(name, () async {
        await expectLater(failing(error).me(), throwsA(isNetwork));
        await expectLater(failing(error).putBlobPart('b', 0, Uint8List(4)), throwsA(isNetwork));
        await expectLater(failing(error).downloadBlob('b', _NullSink()), throwsA(isNetwork));
      });
    }

    test('other errors are not hidden', () async {
      await expectLater(failing(StateError('bug')).me(), throwsA(isA<StateError>()));
    });
  });

  group('attachments', () {
    test('upload of a part: proxy error → unreachable, error of The Vault → ApiException', () async {
      await expectLater(answering(502, '').putBlobPart('b', 0, Uint8List(4)), throwsA(isNetwork));
      await expectLater(answering(503, '<html>down</html>').putBlobPart('b', 0, Uint8List(4)), throwsA(isNetwork));
      await expectLater(answering(409, '{"error":{"code":"blob_complete","message":"done"}}').putBlobPart('b', 0, Uint8List(4)),
          throwsA(isApi(409, 'blob_complete')));
      await answering(204, '').putBlobPart('b', 0, Uint8List(4));
    });

    test('download: proxy error → unreachable, error of The Vault → ApiException', () async {
      await expectLater(answering(504, '').downloadBlob('b', _NullSink()), throwsA(isNetwork));
      await expectLater(answering(503, '<html>down</html>').downloadBlob('b', _NullSink()), throwsA(isNetwork));
      await expectLater(answering(404, '{"error":{"code":"not_found","message":"no such blob"}}').downloadBlob('b', _NullSink()),
          throwsA(isApi(404, 'not_found')));
      final sink = _NullSink();
      expect(await answering(200, 'abc', headers: {'etag': '"x"'}).downloadBlob('b', sink), 'x');
      expect(utf8.decode(sink.bytes), 'abc');
    });

    test('a failure writing the file is not a network problem', () async {
      final err = _NullSink(fail: const FileSystemException('No space left on device'));
      await expectLater(answering(200, 'abc').downloadBlob('b', err), throwsA(isA<FileSystemException>()));
    });
  });
}

/// Collects what is written (or fails like a full disk).
class _NullSink implements IOSink {
  _NullSink({this.fail});
  final Object? fail;
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final b in stream) {
      if (fail != null) throw fail!;
      bytes.addAll(b);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
