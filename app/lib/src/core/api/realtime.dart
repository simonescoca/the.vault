// Real-time channel: a WebSocket that the server uses to push events (new records, approval requests…).
// It reconnects by itself with an increasing delay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class Realtime {
  Realtime({required this.uri, required this.token, this.connector});

  final Uri uri;
  String token;

  /// Replaceable in tests.
  final Future<WebSocket> Function(Uri uri, Map<String, String> headers)? connector;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final connected = ValueNotifier<bool>(false);

  WebSocket? _ws;
  Timer? _retry;
  bool _running = false;
  int _attempt = 0;

  Stream<Map<String, dynamic>> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    connected.value = false;
    await ws?.close(WebSocketStatus.normalClosure);
  }

  /// Reconnect right away (e.g. after the network came back).
  void reconnectNow() {
    if (!_running) return;
    _retry?.cancel();
    if (_ws == null) _connect();
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final headers = {'Authorization': 'Bearer $token'};
      final ws = await (connector?.call(uri, headers) ??
          WebSocket.connect(uri.toString(), headers: headers).timeout(const Duration(seconds: 20)));
      if (!_running) {
        await ws.close();
        return;
      }
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      _attempt = 0;
      connected.value = true;
      ws.listen(
        (msg) {
          if (msg is! String) return;
          try {
            _events.add(Map<String, dynamic>.from(jsonDecode(msg) as Map));
          } catch (_) {}
        },
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onClosed() {
    _ws = null;
    if (!_running || _events.isClosed) return;
    connected.value = false;
    _events.add({'type': 'disconnected'});
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retry?.cancel();
    final seconds = min(30, pow(2, _attempt).toInt());
    _attempt = min(_attempt + 1, 6);
    _retry = Timer(Duration(milliseconds: seconds * 1000 + Random().nextInt(500)), _connect);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    connected.dispose();
  }
}
