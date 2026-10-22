import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/api/realtime.dart';

void main() {
  test('a refused channel waits, but reconnects at once when the server accepts the token again', () async {
    var attempts = 0;
    final rt = Realtime(
      uri: Uri.parse('wss://vault.example.ts.net/v1/ws'),
      token: 'tok',
      connector: (_, _) async {
        attempts++;
        throw const WebSocketException('Connection was not upgraded to websocket', 401);
      },
    );
    final events = <Map<String, dynamic>>[];
    rt.events.listen(events.add);
    rt.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 1);
    expect(events.single, {'type': 'refused', 'status': 401});

    rt.reconnectNow(); // e.g. the 60 s fallback: the refusal is waited out
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 1);

    rt.tokenAccepted(); // a request with the same token succeeded
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 2);

    rt.tokenAccepted(); // refused again: the next acceptance tries again at once too
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 3);
    await rt.dispose();
  });

  test('tokenAccepted does nothing when the channel was not refused', () async {
    var attempts = 0;
    final rt = Realtime(
      uri: Uri.parse('wss://vault.example.ts.net/v1/ws'),
      token: 'tok',
      connector: (_, _) async {
        attempts++;
        throw const SocketException('connection refused');
      },
    );
    rt.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    rt.tokenAccepted();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 1, reason: 'the normal back-off is left alone');
    await rt.dispose();
  });
}
