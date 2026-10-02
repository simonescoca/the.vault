// A signed-in device: local database, server connection, real-time channel, sync and vault.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'account/identity.dart';
import 'api/api_client.dart';
import 'api/realtime.dart';
import 'crypto/vault_crypto.dart';
import 'storage/local_db.dart';
import 'sync/sync_engine.dart';
import 'vault/vault_controller.dart';

class Session {
  Session._({
    required this.identity,
    required this.db,
    required this.api,
    required this.sync,
    required this.vault,
    required this.realtime,
  });

  final Identity identity;
  final LocalDb db;
  final ApiClient api;
  final SyncEngine sync;
  final VaultController vault;
  final Realtime realtime;

  final _approvalRequests = StreamController<ApprovalInfo>.broadcast();
  final _approvalEvents = StreamController<Map<String, dynamic>>.broadcast();

  /// Incremented when the list of devices changes on the server.
  final devicesVersion = ValueNotifier<int>(0);

  /// Called when the server revoked this device (the app must wipe and go back to the start).
  VoidCallback? onRevoked;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _fallback;

  /// New approval requests from other devices.
  Stream<ApprovalInfo> get approvalRequests => _approvalRequests.stream;

  /// All approval.* events (revealed, closed…).
  Stream<Map<String, dynamic>> get approvalEvents => _approvalEvents.stream;

  static Session open({
    required Identity identity,
    required String dataDir,
    required VaultCrypto crypto,
    String locale = 'it',
    String conflictSuffix = ' (conflitto)',
    LocalDb? db,
  }) {
    final database = db ?? LocalDb.open(p.join(dataDir, 'vault.db'));
    final api = ApiClient(base: identity.server, token: identity.token, locale: locale);
    final sync = SyncEngine(
      db: database,
      api: api,
      blobs: BlobFiles(p.join(dataDir, 'blobs')),
      onConflict: (_, _, _) async => false,
    );
    final vault = VaultController(crypto: crypto, db: database, sync: sync, conflictSuffix: conflictSuffix);
    final realtime = Realtime(uri: api.wsUri, token: identity.token);
    final s = Session._(identity: identity, db: database, api: api, sync: sync, vault: vault, realtime: realtime);
    sync.onUnauthorized = () async => s.onRevoked?.call();
    return s;
  }

  void start() {
    _sub = realtime.events.listen(_onEvent);
    realtime.start();
    // When the real-time channel is down, check every minute anyway.
    _fallback = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!realtime.connected.value) {
        realtime.reconnectNow();
        unawaited(sync.sync());
      }
    });
    unawaited(sync.sync());
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'hello':
      case 'records.changed':
        unawaited(sync.sync());
      case 'approval.requested':
        final a = e['approval'];
        if (a is Map) _approvalRequests.add(ApprovalInfo(Map<String, dynamic>.from(a)));
        _approvalEvents.add(e);
      case 'approval.revealed':
      case 'approval.closed':
        _approvalEvents.add(e);
      case 'devices.changed':
        devicesVersion.value++;
      case 'device.revoked':
        onRevoked?.call();
    }
  }

  /// Approval requests already waiting (e.g. arrived while the app was locked).
  Future<List<ApprovalInfo>> pendingApprovals() async {
    try {
      return await api.openApprovals();
    } catch (_) {
      return const [];
    }
  }

  Future<void> close() async {
    _fallback?.cancel();
    await _sub?.cancel();
    await realtime.dispose();
    await sync.dispose();
    vault.dispose();
    api.close();
    db.close();
    await _approvalRequests.close();
    await _approvalEvents.close();
    devicesVersion.dispose();
  }
}
