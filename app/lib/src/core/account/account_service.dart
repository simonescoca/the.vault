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

  /// Checks [vk] against the vault's key check. Only called while joining a vault that exists, so a server that
  /// sends no key check is refused like a wrong key (otherwise any key would be accepted).
  Future<void> _checkKey(ApiClient client, SecureKey vk) async {
    final me = await client.me();
    final kc = (me['vault'] as Map?)?['keyCheck'];
    if (kc is! String) throw CryptoException('the server sent no key check for the vault');
    final Uint8List expected;
    try {
      expected = unb64(kc);
    } on FormatException {
      throw CryptoException('invalid key check');
    }
    final got = crypto.keyCheck(vk);
    if (expected.length != got.length || !crypto.sodium.memcmp(expected, got)) {
      throw CryptoException('the received key does not match this vault');
    }
  }

  /// New device: asks a device already connected for approval.
  ApprovalRequest requestApproval(Identity id) => ApprovalRequest._(this, id);

  /// Removes everything about this device (sign out, revoked device, too many PIN errors).
  Future<void> forgetDevice({Identity? id, bool tellServer = true}) async {
    if (id != null && tellServer) await signOutQuietly(id);
    await secrets.deleteAll();
  }

  /// Signs [id] out on the server, best effort: a short wait, failures (e.g. offline) ignored.
  Future<void> signOutQuietly(Identity id) async {
    try {
      await api(id.server, token: id.token).signOut().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

// ------------------------------------------------------------------ approval: new device

sealed class ApprovalProgress {}

/// Waiting for another device to answer.
class ApprovalWaiting extends ApprovalProgress {}

/// The other device answered: show this verification code and ask whether the other device shows the same
/// ([ApprovalRequest.confirmCode] or [ApprovalRequest.rejectCode]).
class ApprovalCode extends ApprovalProgress {
  ApprovalCode(this.code);
  final String code;
}

class ApprovalGranted extends ApprovalProgress {
  ApprovalGranted(this.vaultKey);
  final SecureKey vaultKey;
}

class ApprovalEnded extends ApprovalProgress {
  ApprovalEnded(this.state, {this.signedOut = false, this.error});

  /// rejected | expired | cancelled | invalid | mismatch (the user saw different codes) | paused | error | offline
  final String state;

  /// This device's registration is gone (signed out, revoked or unknown to the server): start again from the email.
  final bool signedOut;

  /// What went wrong, for 'error'.
  final Object? error;
}

/// The new device's side of the approval (polls the server; the steps are quick).
///
/// The vault key is saved only when both the server says the other device approved and the user confirmed
/// here that the two codes match ([confirmCode]), in either order.
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

  /// The other device's key and nonce, pinned before revealing our nonce: the code shown here is computed from
  /// them, and the vault key must come from that same key.
  Uint8List? _approverKey;
  Uint8List? _approverNonce;
  bool _revealed = false;
  bool _confirmed = false;

  /// The server said 'approved' (this device is active there now).
  bool _approved = false;

  /// Opened and checked, waiting for the user's confirmation.
  SecureKey? _key;
  bool _done = false;

  /// The vault key is being saved (ApprovalGranted follows).
  bool _granted = false;

  /// How it ended, when it did.
  bool _signedOut = false;
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
      if (e.status == 401 || e.code == 'device_revoked') {
        _finish('cancelled', signedOut: true); // unknown or revoked: start again from the email
      } else if (e.status == 403) {
        // No longer pending (e.g. approved, then the code was refused here while offline): unlink it.
        await _svc.forgetDevice(id: _id);
        _finish('cancelled', signedOut: true);
      } else {
        _finish(e.status == 429 ? 'paused' : 'error', error: e);
      }
    } on NetworkException {
      _finish('offline');
    }
  }

  bool _polling = false;

  Future<void> _poll() async {
    if (_done || _polling || _approvalId == null || _key != null) return;
    _polling = true;
    try {
      final a = await _api.approval(_approvalId!);
      if (_done) return;
      switch (a.state) {
        case 'responded' when !_revealed:
          if (!_pin(a)) return await _refuse('invalid');
          await _api.revealApproval(_approvalId!, _nonce);
          _showCode();
        case 'revealed' when !_revealed:
          // Our reveal reached the server but its answer got lost: valid only with the key and nonce pinned
          // before revealing (afterwards the server knows our nonce and could pick others that give the same code).
          if (_approverKey == null || !_pin(a)) return await _refuse('invalid');
          _showCode();
        case 'approved':
          _approved = true;
          // Our reveal reached the server (it approves only after it) but its answer got lost: same rule as
          // 'revealed' above. The user still has to confirm the code here.
          if (!_revealed && _approverKey != null && _pin(a)) _showCode();
          await _onApproved(a);
        case 'rejected' || 'expired' || 'cancelled':
          _finish(a.state);
      }
    } on NetworkException {
      // try again at the next tick
    } on ApiException catch (e) {
      // The request or this device is gone (no vault data here yet, nothing to keep).
      if (e.status == 401 || e.code == 'device_revoked') {
        _finish('cancelled', signedOut: true);
      } else if (e.status == 404) {
        _finish('cancelled');
      }
    } finally {
      _polling = false;
    }
  }

  /// Pins the other device's key and nonce, or checks that they did not change. False if they are missing,
  /// malformed or different from the pinned ones.
  bool _pin(ApprovalInfo a) {
    final pk = a.responderPublicKey, n = a.responderNonce;
    if (pk == null || n == null || pk.length != 32 || n.length != 32) return false;
    if (_approverKey == null) {
      _approverKey = pk;
      _approverNonce = n;
      return true;
    }
    return _same(_approverKey!, pk) && _same(_approverNonce!, n);
  }

  /// Constant-time comparison.
  bool _same(Uint8List a, Uint8List b) => a.length == b.length && _svc.crypto.sodium.memcmp(a, b);

  void _showCode() {
    _revealed = true;
    _emit(ApprovalCode(_svc.crypto.approvalCode(
      approvalId: _approvalId!,
      newDevicePublicKey: _id.devicePublicKey,
      approverPublicKey: _approverKey!,
      approverNonce: _approverNonce!,
      newDeviceNonce: _nonce,
    )));
  }

  /// The other device approved: opens the vault key with the pinned key and checks it, then waits for the
  /// user's confirmation (if not given yet).
  Future<void> _onApproved(ApprovalInfo a) async {
    final pk1 = _approverKey;
    final got = a.responderPublicKey;
    final box = a.box, boxNonce = a.boxNonce;
    // Approved without the code shown here, or with another key than the one the code covers: tampering.
    if (!_revealed || pk1 == null || got == null || !_same(pk1, got) || box == null || boxNonce == null) {
      return _refuse('invalid');
    }
    final sk = SecureKey.fromList(_svc.crypto.sodium, _id.deviceSecretKey);
    final SecureKey vk;
    try {
      vk = _svc.crypto.openVaultKey(
        box: box,
        nonce: boxNonce,
        approverPublicKey: pk1,
        deviceSecretKey: sk,
        userId: _id.userId,
        approvalId: _approvalId!,
      );
    } on CryptoException {
      return _refuse('invalid');
    } finally {
      sk.dispose();
    }
    try {
      await _svc._checkKey(_api, vk);
    } on CryptoException {
      vk.dispose();
      return _refuse('invalid');
    } catch (_) {
      vk.dispose();
      rethrow; // network or server error: try again at the next tick
    }
    if (_done) {
      vk.dispose();
      return;
    }
    _timer?.cancel(); // nothing more to ask the server
    _key = vk;
    if (_confirmed) await _grant();
  }

  /// The user saw the same code on both devices.
  Future<void> confirmCode() async {
    if (_done || !_revealed) return;
    _confirmed = true;
    if (_key != null) await _grant();
  }

  /// The user saw different codes: someone may be in the middle. Cancels the request on the server; if the
  /// server already approved this device, signs it out instead (it must not stay linked without the key).
  Future<void> rejectCode() async {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _key?.dispose();
    _key = null;
    final signedOut = await _withdraw();
    _end(ApprovalEnded('mismatch', signedOut: signedOut));
  }

  /// Cancels the request on the server. If the server already approved this device (it is no longer pending),
  /// signs it out instead: it must not stay linked without the key. Returns whether it was signed out.
  Future<bool> _withdraw() async {
    var signOut = _approved;
    final id = _approvalId;
    if (!signOut && id != null) {
      try {
        await _api.cancelApproval(id);
      } on ApiException catch (e) {
        // 403: approved meanwhile (no longer pending); 401 or device_revoked: the registration is gone.
        signOut = e.status == 401 || e.status == 403 || e.code == 'device_revoked';
      } on NetworkException {
        // the request expires by itself
      }
    }
    if (signOut) await _svc.forgetDevice(id: _id);
    return signOut;
  }

  Future<void> _grant() async {
    final vk = _key!;
    _key = null;
    _done = true;
    _granted = true;
    _timer?.cancel();
    await _svc.secrets.writeVaultKey(vk.extractBytes());
    _id.status = 'active';
    await _svc.secrets.writeIdentity(_id);
    _emit(ApprovalGranted(vk));
  }

  /// Ends without the vault key. If the server already approved this device, it is signed out.
  Future<void> _refuse(String state) async {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _key?.dispose();
    _key = null;
    if (_approved) await _svc.forgetDevice(id: _id);
    _end(ApprovalEnded(state, signedOut: _approved));
  }

  void _finish(String state, {bool signedOut = false, Object? error}) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _end(ApprovalEnded(state, signedOut: signedOut, error: error));
  }

  void _end(ApprovalEnded e) {
    _signedOut = e.signedOut;
    _emit(e);
  }

  void _emit(ApprovalProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  /// The user gave up (or chose the emergency code instead). [cancelled] is false when the vault key is
  /// already being saved: ApprovalGranted follows. [signedOut]: this device's registration is gone (e.g. the
  /// server had already approved it, so it was signed out): start again from the email.
  Future<({bool cancelled, bool signedOut})> cancel() async {
    if (_granted) return (cancelled: false, signedOut: false);
    var signedOut = _signedOut;
    if (!_done) {
      _done = true;
      _timer?.cancel();
      _key?.dispose();
      _key = null;
      signedOut = await _withdraw();
    }
    await _progress.close();
    return (cancelled: true, signedOut: signedOut);
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
