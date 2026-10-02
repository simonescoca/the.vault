// Starts the real Go server (../server) for integration tests.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

class TestServer {
  TestServer._(this.process, this.dataDir, this.port);

  final Process process;
  final Directory dataDir;
  final int port;

  Uri get url => Uri.parse('http://127.0.0.1:$port');

  static String? _binary;

  static Future<String> _build() async {
    if (_binary != null) return _binary!;
    final out = '${Directory.systemTemp.path}/thevault-server-test-$pid';
    final r = await Process.run('go', ['build', '-o', out, './cmd/thevault-server'], workingDirectory: '../server');
    if (r.exitCode != 0) throw StateError('go build failed: ${r.stderr}');
    return _binary = out;
  }

  static Future<TestServer> start({String email = 'me@example.com'}) async {
    final bin = await _build();
    final dir = await Directory.systemTemp.createTemp('tvs-data');
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = sock.port;
    await sock.close();
    final secret = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    File('${dir.path}/config.json').writeAsStringSync(jsonEncode({
      'listen': '127.0.0.1:$port',
      'allowedEmails': [email],
      'serverSecret': secret,
      'mailMode': 'log',
      'testMode': true,
      'logLevel': 'warn',
    }));
    final proc = await Process.start(bin, ['serve', '--data', dir.path]);
    proc.stderr.transform(utf8.decoder).listen((l) {
      if (l.contains('level=ERROR')) stderr.write('[server] $l');
    });
    final s = TestServer._(proc, dir, port);
    for (var i = 0; i < 100; i++) {
      try {
        final r = await http.get(s.url.replace(path: '/v1/health'));
        if (r.statusCode == 200) return s;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('server did not start');
  }

  /// The last login code sent to [email] (read from the server's mail log).
  String lastCode() {
    final log = File('${dataDir.path}/mail.log').readAsStringSync();
    final m = RegExp(r'(\d{3}) (\d{3})').allMatches(log).toList();
    if (m.isEmpty) throw StateError('no code in mail.log');
    return '${m.last.group(1)}${m.last.group(2)}';
  }

  String get mailLog => File('${dataDir.path}/mail.log').readAsStringSync();

  Future<void> stop() async {
    process.kill();
    await process.exitCode;
    await dataDir.delete(recursive: true);
  }
}
