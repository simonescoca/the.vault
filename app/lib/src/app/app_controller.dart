// Top-level state of the app: first access, locked, unlocked (docs/SPEC.md §2-3).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import '../core/account/account_service.dart';
import '../core/account/identity.dart';
import '../core/api/api_client.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/session.dart';
import '../core/storage/secret_store.dart';
import 'lock_service.dart';
import 'platform_services.dart';
import 'settings.dart';

enum AppPhase { loading, onboarding, needsPin, locked, unlocked }

/// One-off messages for the UI.
enum AppNotice { deviceRevoked, pinWiped, clipboardCleared }

class AppController extends ChangeNotifier {
  AppController({
    required this.crypto,
    required this.secrets,
    required this.platform,
    required this.settings,
    required this.dataDir,
    this.version = '1.0.0',
    this.online = true,
  })  : account = AccountService(crypto: crypto, secrets: secrets),
        lock = LockService(secrets, platform);

  final VaultCrypto crypto;
  final SecretStore secrets;
  final PlatformServices platform;
  final AppSettings settings;
  final String dataDir;
  final String version;

  /// False in UI tests: no connection to a server.
  final bool online;
  final AccountService account;
  final LockService lock;

  AppPhase phase = AppPhase.loading;
  Identity? identity;
  Session? session;

  final _notices = StreamController<AppNotice>.broadcast();
  Stream<AppNotice> get notices => _notices.stream;

  /// Approval requests from new devices, to show while unlocked.
  final _approvals = StreamController<ApprovalInfo>.broadcast();
  Stream<ApprovalInfo> get approvalRequests => _approvals.stream;

  /// Number of approval requests waiting (shown on the lock screen).
  final pendingApprovalCount = ValueNotifier<int>(0);

  Timer? _idle;
  Timer? _sleepWatch;
  DateTime _lastTick = DateTime.now();
  Timer? _clipboardTimer;
  StreamSubscription<ApprovalInfo>? _approvalSub;

  String get openDir => p.join(dataDir, 'open');

  void _set(AppPhase p) {
    phase = p;
    notifyListeners();
  }

  Future<void> init() async {
    account.locale = _lang;
    await _clearOpenDir();
    final id = await secrets.readIdentity();
    final vk = await secrets.readVaultKey();
    if (id == null || !id.isActive || vk == null) {
      if (id != null) await _wipeLocal();
      _set(AppPhase.onboarding);
      return;
    }
    identity = id;
    _openSession(id);
    _set(await lock.hasPin() ? AppPhase.locked : AppPhase.needsPin);
  }

  String get _lang => settings.effectiveLocale(PlatformDispatcher.instance.locale).languageCode;

  String get conflictSuffix => _lang == 'it' ? ' (conflitto)' : ' (conflict)';

  void _openSession(Identity id) {
    final s = session = Session.open(
      identity: id,
      dataDir: dataDir,
      crypto: crypto,
      locale: _lang,
      conflictSuffix: conflictSuffix,
    );
    s.onRevoked = () => unawaited(_revoked());
    _approvalSub = s.approvalRequests.listen((a) {
      if (phase == AppPhase.unlocked) {
        _approvals.add(a);
      } else {
        pendingApprovalCount.value++;
      }
    });
    if (online) {
      s.start();
    } else {
      s.sync.enabled = false;
    }
  }

  /// Called by onboarding once this device has the vault key.
  Future<void> onboardingDone(Identity id, SecureKey vaultKey) async {
    identity = id;
    _openSession(id);
    session!.vault.unlock(vaultKey);
    _set(await lock.hasPin() ? AppPhase.unlocked : AppPhase.needsPin);
    if (phase == AppPhase.unlocked) _afterUnlock();
  }

  /// PIN chosen (first access, or after an interrupted first access).
  Future<void> pinChosen(String pin) async {
    await lock.setPin(pin);
    if (session?.vault.isUnlocked != true) {
      final vk = await secrets.readVaultKey();
      if (vk == null) return wipeDevice();
      session!.vault.unlock(crypto.keyFromBytes(vk));
    }
    _set(AppPhase.unlocked);
    _afterUnlock();
  }

  // ------------------------------------------------------------------ unlock

  Future<bool> unlockWithBiometrics() async {
    if (!await lock.canUseBiometrics()) return false;
    final ok = await platform.authenticate(_lang == 'it' ? 'Sblocca The Vault' : 'Unlock The Vault');
    if (!ok) return false;
    return _unlock();
  }

  Future<PinResult> unlockWithPin(String pin) async {
    final r = await lock.verifyPin(pin);
    switch (r) {
      case PinOk():
        await _unlock();
      case PinWipe():
        await wipeDevice(tellServer: false);
        _notices.add(AppNotice.pinWiped);
      default:
    }
    return r;
  }

  Future<bool> _unlock() async {
    final vk = await secrets.readVaultKey();
    final s = session;
    if (vk == null || s == null) {
      await wipeDevice(tellServer: false);
      return false;
    }
    s.vault.unlock(crypto.keyFromBytes(vk));
    _set(AppPhase.unlocked);
    _afterUnlock();
    return true;
  }

  void _afterUnlock() {
    registerActivity();
    _lastTick = DateTime.now();
    _sleepWatch?.cancel();
    _sleepWatch = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      // A long gap between ticks means the computer was asleep: lock.
      if (now.difference(_lastTick) > const Duration(seconds: 45)) lockNow();
      _lastTick = now;
    });
    pendingApprovalCount.value = 0;
    unawaited(() async {
      for (final a in await session!.pendingApprovals()) {
        _approvals.add(a);
      }
    }());
  }

  /// Any user activity postpones the automatic lock.
  void registerActivity() {
    if (phase != AppPhase.unlocked) return;
    _idle?.cancel();
    _idle = Timer(Duration(minutes: settings.autoLockMinutes), lockNow);
  }

  void lockNow() {
    if (phase != AppPhase.unlocked) return;
    _idle?.cancel();
    _sleepWatch?.cancel();
    session?.vault.lock();
    unawaited(_clearOpenDir());
    _set(AppPhase.locked);
  }

  // ---------------------------------------------------------------- clipboard

  /// Copies [text] and clears the clipboard after the configured time if it still holds it.
  Future<void> copy(String text) async {
    await platform.setClipboard(text);
    _clipboardTimer?.cancel();
    final secs = settings.clipboardSeconds;
    if (secs <= 0) return;
    _clipboardTimer = Timer(Duration(seconds: secs), () async {
      if (await platform.getClipboard() == text) {
        await platform.setClipboard('');
        _notices.add(AppNotice.clipboardCleared);
      }
    });
  }

  // ------------------------------------------------------------------- reset

  Future<void> _revoked() async {
    await wipeDevice(tellServer: false);
    _notices.add(AppNotice.deviceRevoked);
  }

  /// Signs out (or forgets a revoked device): deletes every local trace.
  Future<void> wipeDevice({bool tellServer = true}) async {
    _idle?.cancel();
    _sleepWatch?.cancel();
    await _approvalSub?.cancel();
    final id = identity;
    if (tellServer && id != null) {
      try {
        await ApiClient(base: id.server, token: id.token).signOut();
      } catch (_) {}
    }
    await session?.close();
    session = null;
    identity = null;
    await _wipeLocal();
    _set(AppPhase.onboarding);
  }

  Future<void> _wipeLocal() async {
    await secrets.deleteAll();
    for (final name in ['vault.db', 'vault.db-wal', 'vault.db-shm']) {
      final f = File(p.join(dataDir, name));
      if (await f.exists()) await f.delete();
    }
    for (final d in ['blobs', 'open']) {
      final dir = Directory(p.join(dataDir, d));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<void> _clearOpenDir() async {
    final dir = Directory(openDir);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Bytes of the vault key (for approvals of new devices). Only while unlocked.
  SecureKey get vaultKey => session!.vault.vaultKey;

  Uint8List? get devicePublicKey => identity?.devicePublicKey;

  @override
  void dispose() {
    _idle?.cancel();
    _sleepWatch?.cancel();
    _clipboardTimer?.cancel();
    unawaited(_approvalSub?.cancel());
    unawaited(session?.close());
    _notices.close();
    _approvals.close();
    pendingApprovalCount.dispose();
    super.dispose();
  }
}
