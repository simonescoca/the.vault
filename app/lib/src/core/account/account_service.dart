// First access of a device: server, email code, then either creating the vault (first device),
// approval from another device, or the emergency code (docs/SECURITY.md §6-8).
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sodium/sodium_sumo.dart';

import '../api/api_client.dart';
import '../crypto/recovery_code.dart';
import '../crypto/vault_crypto.dart';
import '../storage/secret_store.dart';
import 'identity.dart';

/// Another device created the vault first: this device needs approval.
class AlreadyInitialized implements Exception {}

class AccountService {
  AccountService({required this.crypto, required this.secrets, this.locale = 'it', this.httpClient});

  final VaultCrypto crypto;
  final SecretStore secrets;
  String locale;
  final http.Client? httpClient;

  ApiClient api(Uri server, {String? token}) => ApiClient(base: server, token: token, locale: locale, client: httpClient);

  /// Checks that [input] points to a The Vault server and returns its normalized address.
  Future<Uri> checkServer(String input) async {
    final u = ApiClient.normalizeServer(input);
    if (u == null) throw const FormatException('invalid server address');
    await api(u).health();
    return u;
  }

  Future<void> requestCode(Uri server, String email, {String? deviceName}) =>
      api(server).requestCode(email.trim(), deviceName: deviceName);

  /// Verifies the email code and registers this device. The identity is saved in the keychain.
  Future<Identity> verifyCode({
    required Uri server,
    required String email,
    required String code,
    required String deviceName,
    required String platform,
  }) async {
    final kp = crypto.newBoxKeyPair();
    try {
      final r = await api(server).verifyCode(
        email: email.trim(),
        code: code,
        deviceName: deviceName,
        platform: platform,
        publicKey: kp.publicKey,
      );
      final id = Identity(
        server: server,
        email: email.trim().toLowerCase(),
        userId: r.userId,
        deviceId: r.deviceId,
        deviceName: deviceName,
        platform: platform,
        token: r.token,
        devicePublicKey: kp.publicKey,
        deviceSecretKey: kp.secretKey.extractBytes(),
        status: r.status,
      );
      await secrets.writeIdentity(id);
      return id;
    } finally {
      kp.secretKey.dispose();
    }
  }

  /// First device: creates the vault key and the emergency kit. Returns the emergency code to show.
  /// Throws [AlreadyInitialized] if another device was faster (then use the approval flow).
  Future<({RecoveryCode code, SecureKey vaultKey})> createVault(Identity id) async {
    final vk = crypto.newVaultKey();
    final rec = await crypto.createRecovery(vk, id.userId);
    try {
      await api(id.server, token: id.token).initVault(
        keyCheck: crypto.keyCheck(vk),
        recovery: rec.bundle,
        recoveryAuth: rec.authKey,
      );
    } on ApiException catch (e) {
      if (e.code == 'already_initialized') {
        id.status = 'pending';
        await secrets.writeIdentity(id);
        vk.dispose();
        throw AlreadyInitialized();
      }
      vk.dispose();
      rethrow;
    }
    await secrets.writeVaultKey(vk.extractBytes());
    id.status = 'active';
    await secrets.writeIdentity(id);
    return (code: rec.code, vaultKey: vk);
  }

  /// New device without other devices: opens the vault with the emergency code.
  /// Throws [CryptoException] if the code is wrong.
  Future<SecureKey> useRecoveryCode(Identity id, RecoveryCode code) async {
    final client = api(id.server, token: id.token);
    final bundle = await client.recovery();
    final opened = await crypto.openRecovery(bundle, code, id.userId);
    await _checkKey(client, opened.vaultKey);
    await client.activateRecovery(opened.authKey);
    await secrets.writeVaultKey(opened.vaultKey.extractBytes());
    id.status = 'active';
    await secrets.writeIdentity(id);
    return opened.vaultKey;
  }

  /// Replaces the emergency kit (Settings › New emergency code). Returns the new code.
  Future<RecoveryCode> replaceRecovery(Identity id, SecureKey vaultKey) async {
    final rec = await crypto.createRecovery(vaultKey, id.userId);
    await api(id.server, token: id.token).replaceRecovery(rec.bundle, rec.authKey);
    return rec.code;
  }

  Future<void> _checkKey(ApiClient client, SecureKey vk) async {
    final me = await client.me();
    final kc = (me['vault'] as Map?)?['keyCheck'] as String?;
    if (kc == null) return;
    final expected = unb64(kc);
    final got = crypto.keyCheck(vk);
    if (!crypto.sodium.memcmp(expected, got)) {
      throw CryptoException('the received key does not match this vault');
    }
  }

  /// New device: asks a device already connected for approval.
  ApprovalRequest requestApproval(Identity id) => ApprovalRequest._(this, id);

  /// Removes everything about this device (sign out, revoked device, too many PIN errors).
  Future<void> forgetDevice({Identity? id, bool tellServer = true}) async {
    if (id != null && tellServer) {
      try {
        await api(id.server, token: id.token).signOut();
      } catch (_) {}
    }
    await secrets.deleteAll();
  }
}

// ------------------------------------------------------------------ approval: new device

sealed class ApprovalProgress {}

/// Waiting for another device to answer.
class ApprovalWaiting extends ApprovalProgress {}

/// The other device answered: show this verification code.
class ApprovalCode extends ApprovalProgress {
  ApprovalCode(this.code);
  final String code;
}

class ApprovalGranted extends ApprovalProgress {
  ApprovalGranted(this.vaultKey);
  final SecureKey vaultKey;
}

class ApprovalEnded extends ApprovalProgress {
  ApprovalEnded(this.state);

  /// rejected | expired | cancelled | invalid
  final String state;
}

/// The new device's side of the approval (polls the server; the steps are quick).
class ApprovalRequest {
  ApprovalRequest._(this._svc, this._id) {
    _start();
  }

  final AccountService _svc;
  final Identity _id;
  final _progress = StreamController<ApprovalProgress>.broadcast();
  late final ApiClient _api = _svc.api(_id.server, token: _id.token);
  late final Uint8List _nonce = _svc.crypto.randomBytes(32);
  String? _approvalId;
  bool _revealed = false;
  bool _done = false;
  Timer? _timer;

  Stream<ApprovalProgress> get progress => _progress.stream;

  /// Poll interval (shorter in tests).
  static Duration pollEvery = const Duration(milliseconds: 1500);

  Future<void> _start() async {
    _progress.add(ApprovalWaiting());
    try {
      final commitment = _svc.crypto.approvalCommitment(_id.devicePublicKey, _nonce);
      _approvalId = await _api.createApproval(commitment);
      _timer = Timer.periodic(pollEvery, (_) => _poll());
    } on ApiException catch (e) {
      _finish(e.status == 429 ? 'paused' : 'error');
    } on NetworkException {
      _finish('offline');
    }
  }

  bool _polling = false;

  Future<void> _poll() async {
    if (_done || _polling || _approvalId == null) return;
    _polling = true;
    try {
      final a = await _api.approval(_approvalId!);
      switch (a.state) {
        case 'responded' when !_revealed:
          await _api.revealApproval(a.id, _nonce);
          _revealed = true;
          _progress.add(ApprovalCode(_code(a)));
        case 'revealed' when !_revealed:
          _revealed = true;
          _progress.add(ApprovalCode(_code(a)));
        case 'approved':
          final sk = SecureKey.fromList(_svc.crypto.sodium, _id.deviceSecretKey);
          try {
            final vk = _svc.crypto.openVaultKey(
              box: a.box!,
              nonce: a.boxNonce!,
              approverPublicKey: a.responderPublicKey!,
              deviceSecretKey: sk,
              userId: _id.userId,
              approvalId: a.id,
            );
            await _svc._checkKey(_api, vk);
            await _svc.secrets.writeVaultKey(vk.extractBytes());
            _id.status = 'active';
            await _svc.secrets.writeIdentity(_id);
            _done = true;
            _timer?.cancel();
            _progress.add(ApprovalGranted(vk));
          } on CryptoException {
            _finish('invalid');
          } finally {
            sk.dispose();
          }
        case 'rejected' || 'expired' || 'cancelled':
          _finish(a.state);
      }
    } on NetworkException {
      // try again at the next tick
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 404) _finish('cancelled');
    } finally {
      _polling = false;
    }
  }

  String _code(ApprovalInfo a) => _svc.crypto.approvalCode(
        approvalId: a.id,
        newDevicePublicKey: _id.devicePublicKey,
        approverPublicKey: a.responderPublicKey!,
        approverNonce: a.responderNonce!,
        newDeviceNonce: _nonce,
      );

  void _finish(String state) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _progress.add(ApprovalEnded(state));
  }

  /// The user gave up (or chose the emergency code instead).
  Future<void> cancel() async {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    final id = _approvalId;
    if (id != null) {
      try {
        await _api.cancelApproval(id);
      } catch (_) {}
    }
    await _progress.close();
  }
}

// ------------------------------------------------------------ approval: connected device

/// The approver's side: answers a request, then shows the code and approves or rejects.
class ApprovalResponse {
  ApprovalResponse(this._crypto, this._api, this.request);

  final VaultCrypto _crypto;
  final ApiClient _api;
  final ApprovalInfo request;

  KeyPair? _ephemeral;
  late final Uint8List _nonce = _crypto.randomBytes(32);
  ApprovalInfo? _revealed;

  static Duration pollEvery = const Duration(milliseconds: 1000);

  /// Claims the request and waits for the new device to reveal its nonce. Returns the 6-digit code,
  /// or throws [CryptoException] if the commitment does not match (someone is tampering).
  Future<String> start({Duration timeout = const Duration(minutes: 5)}) async {
    final kp = _ephemeral = _crypto.newBoxKeyPair();
    await _api.respondApproval(request.id, kp.publicKey, _nonce);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final a = await _api.approval(request.id);
      if (a.state == 'revealed') {
        _revealed = a;
        return _codeFor(a);
      }
      if (a.state != 'responded') throw ApprovalClosed(a.state);
      await Future<void>.delayed(pollEvery);
    }
    throw ApprovalClosed('expired');
  }

  /// Same as [start] but driven by a `approval.revealed` real-time event.
  String onRevealed(ApprovalInfo a) {
    _revealed = a;
    return _codeFor(a);
  }

  String _codeFor(ApprovalInfo a) {
    final pk2 = request.devicePublicKey!;
    final n2 = a.revealedNonce!;
    final expected = _crypto.approvalCommitment(pk2, n2);
    if (!_crypto.sodium.memcmp(expected, request.commitment)) {
      throw CryptoException('commitment mismatch');
    }
    return _crypto.approvalCode(
      approvalId: request.id,
      newDevicePublicKey: pk2,
      approverPublicKey: _ephemeral!.publicKey,
      approverNonce: _nonce,
      newDeviceNonce: n2,
    );
  }

  /// The user confirmed that the codes match.
  Future<void> approve({required SecureKey vaultKey, required String userId}) async {
    final kp = _ephemeral;
    if (kp == null || _revealed == null) throw StateError('code not verified yet');
    final sealed = _crypto.sealVaultKey(
      vaultKey: vaultKey,
      userId: userId,
      approvalId: request.id,
      newDevicePublicKey: request.devicePublicKey!,
      approverSecretKey: kp.secretKey,
    );
    await _api.approveApproval(request.id, sealed.box, sealed.nonce);
    _dispose();
  }

  Future<void> reject() async {
    try {
      await _api.rejectApproval(request.id);
    } finally {
      _dispose();
    }
  }

  void _dispose() {
    _ephemeral?.secretKey.dispose();
    _ephemeral = null;
  }
}

class ApprovalClosed implements Exception {
  ApprovalClosed(this.state);
  final String state;
}
