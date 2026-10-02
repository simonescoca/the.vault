// End-to-end cryptography of The Vault (see docs/SECURITY.md).
//
// Everything is built on libsodium:
// - records: XChaCha20-Poly1305 with a key derived from the vault key, AAD bound to the record id;
// - attachments: secretstream XChaCha20-Poly1305 (see file_crypto.dart);
// - device approval: commitment + short authentication string + crypto_box;
// - emergency kit: Argon2id-derived key wrapping the vault key.
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'recovery_code.dart';

class CryptoException implements Exception {
  CryptoException(this.message);
  final String message;
  @override
  String toString() => 'CryptoException: $message';
}

/// Parameters and output of the emergency-kit key wrapping.
class RecoveryBundle {
  RecoveryBundle({
    required this.salt,
    required this.opsLimit,
    required this.memLimit,
    required this.wrap,
  });

  final Uint8List salt;
  final int opsLimit;
  final int memLimit;

  /// nonce (24) ‖ AEAD(vault key) (48)
  final Uint8List wrap;
}

/// Result of creating an emergency kit.
class NewRecovery {
  NewRecovery({required this.code, required this.bundle, required this.authKey});
  final RecoveryCode code;
  final RecoveryBundle bundle;

  /// Sent to the server once; the server stores its SHA-256 and checks it on recovery.
  final Uint8List authKey;
}

/// Raw key material derived from an emergency code.
class _RecoveryKeys {
  _RecoveryKeys(this.wrapKey, this.authKey);
  final Uint8List wrapKey;
  final Uint8List authKey;
}

class VaultCrypto {
  VaultCrypto(this.sodium);

  final SodiumSumo sodium;

  static const recordVersion = 1;
  static const _padBlock = 256;

  static Future<VaultCrypto> init() async => VaultCrypto(await SodiumSumoInit.init());

  Uint8List randomBytes(int n) => sodium.randombytes.buf(n);

  // ---------------------------------------------------------------- vault key

  /// A new random 32-byte vault key.
  SecureKey newVaultKey() => sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  SecureKey keyFromBytes(Uint8List bytes) {
    if (bytes.length != 32) throw CryptoException('invalid key length ${bytes.length}');
    return SecureKey.fromList(sodium, bytes);
  }

  SecureKey _derive(SecureKey master, int id, String context) => sodium.crypto.kdf.deriveFromKey(
        masterKey: master,
        context: context,
        subkeyId: BigInt.from(id),
        subkeyLen: 32,
      );

  /// Key used to encrypt the records.
  SecureKey itemsKey(SecureKey vaultKey) => _derive(vaultKey, 1, 'tv_items');

  /// 16-byte value stored on the server to check that a device received the right vault key.
  Uint8List keyCheck(SecureKey vaultKey) {
    final k = _derive(vaultKey, 2, 'tv_check');
    try {
      return sodium.crypto.genericHash(
        message: _utf8('thevault/key-check/v1'),
        outLen: 16,
        key: k,
      );
    } finally {
      k.dispose();
    }
  }

  // ------------------------------------------------------------------ records

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  Uint8List _recordAad(String recordId) => _utf8('thevault/item/v1/$recordId');

  /// `0x01 ‖ nonce(24) ‖ XChaCha20-Poly1305(pad(plaintext))`.
  Uint8List encryptRecord(SecureKey itemsKey, String recordId, Uint8List plaintext) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = randomBytes(aead.nonceBytes);
    final padded = sodium.pad(plaintext, _padBlock);
    final ct = aead.encrypt(
      message: padded,
      nonce: nonce,
      key: itemsKey,
      additionalData: _recordAad(recordId),
    );
    final out = Uint8List(1 + nonce.length + ct.length);
    out[0] = recordVersion;
    out.setRange(1, 1 + nonce.length, nonce);
    out.setRange(1 + nonce.length, out.length, ct);
    return out;
  }

  Uint8List decryptRecord(SecureKey itemsKey, String recordId, Uint8List data) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final n = aead.nonceBytes;
    if (data.length < 1 + n + aead.aBytes || data[0] != recordVersion) {
      throw CryptoException('unsupported or truncated record');
    }
    try {
      final padded = aead.decrypt(
        cipherText: Uint8List.sublistView(data, 1 + n),
        nonce: Uint8List.sublistView(data, 1, 1 + n),
        key: itemsKey,
        additionalData: _recordAad(recordId),
      );
      return sodium.unpad(padded, _padBlock);
    } on SodiumException {
      throw CryptoException('record authentication failed');
    }
  }

  // ------------------------------------------------------------ emergency kit

  static Uint8List _recoveryAad(String userId) => _utf8('thevault/recovery/v1/$userId');

  /// Argon2id + KDF, in a background isolate (it takes a moment by design).
  static Future<_RecoveryKeys> _recoveryKeys(Uint8List code, Uint8List salt, int ops, int mem) {
    return Isolate.run(() async {
      final s = await SodiumSumoInit.init();
      final rk = s.crypto.pwhash.callRaw(
        outLen: 32,
        password: Int8List.fromList(code),
        salt: salt,
        opsLimit: ops,
        memLimit: mem,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      try {
        final wrap = s.crypto.kdf.deriveFromKey(masterKey: rk, context: 'tv_rcvry', subkeyId: BigInt.one, subkeyLen: 32);
        final auth = s.crypto.kdf.deriveFromKey(masterKey: rk, context: 'tv_rauth', subkeyId: BigInt.two, subkeyLen: 32);
        final out = _RecoveryKeys(wrap.extractBytes(), auth.extractBytes());
        wrap.dispose();
        auth.dispose();
        return out;
      } finally {
        rk.dispose();
      }
    });
  }

  /// Creates a new emergency code and wraps the vault key with it.
  Future<NewRecovery> createRecovery(SecureKey vaultKey, String userId) async {
    final code = RecoveryCode.random(randomBytes(RecoveryCode.byteLength));
    final pw = sodium.crypto.pwhash;
    final salt = randomBytes(pw.saltBytes);
    final ops = pw.opsLimitInteractive;
    final mem = pw.memLimitInteractive;
    final keys = await _recoveryKeys(code.bytes, salt, ops, mem);
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = randomBytes(aead.nonceBytes);
    final wrapKey = SecureKey.fromList(sodium, keys.wrapKey);
    try {
      final ct = vaultKey.runUnlockedSync((vk) => aead.encrypt(
            message: Uint8List.fromList(vk),
            nonce: nonce,
            key: wrapKey,
            additionalData: _recoveryAad(userId),
          ));
      return NewRecovery(
        code: code,
        bundle: RecoveryBundle(salt: salt, opsLimit: ops, memLimit: mem, wrap: Uint8List.fromList([...nonce, ...ct])),
        authKey: keys.authKey,
      );
    } finally {
      wrapKey.dispose();
    }
  }

  /// Opens an emergency kit. Throws [CryptoException] if the code is wrong.
  Future<({SecureKey vaultKey, Uint8List authKey})> openRecovery(
    RecoveryBundle bundle,
    RecoveryCode code,
    String userId,
  ) async {
    final keys = await _recoveryKeys(code.bytes, bundle.salt, bundle.opsLimit, bundle.memLimit);
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final n = aead.nonceBytes;
    if (bundle.wrap.length != n + 32 + aead.aBytes) throw CryptoException('invalid emergency kit');
    final wrapKey = SecureKey.fromList(sodium, keys.wrapKey);
    try {
      final vk = aead.decrypt(
        cipherText: Uint8List.sublistView(bundle.wrap, n),
        nonce: Uint8List.sublistView(bundle.wrap, 0, n),
        key: wrapKey,
        additionalData: _recoveryAad(userId),
      );
      final key = SecureKey.fromList(sodium, vk);
      vk.fillRange(0, vk.length, 0);
      return (vaultKey: key, authKey: keys.authKey);
    } on SodiumException {
      throw CryptoException('wrong emergency code');
    } finally {
      wrapKey.dispose();
    }
  }

  // ---------------------------------------------------------- device approval

  /// X25519 key pair (device key, or the approver's ephemeral key).
  KeyPair newBoxKeyPair() => sodium.crypto.box.keyPair();

  Uint8List _hash(List<Uint8List> parts, {int outLen = 32}) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(p);
    }
    return sodium.crypto.genericHash(message: b.toBytes(), outLen: outLen);
  }

  /// Commitment of the new device to its public key and secret nonce.
  Uint8List approvalCommitment(Uint8List devicePublicKey, Uint8List secretNonce) =>
      _hash([_utf8('thevault/approval/commit/v1'), devicePublicKey, secretNonce]);

  /// The 6-digit verification code shown on both devices.
  String approvalCode({
    required String approvalId,
    required Uint8List newDevicePublicKey,
    required Uint8List approverPublicKey,
    required Uint8List approverNonce,
    required Uint8List newDeviceNonce,
  }) {
    final h = _hash([
      _utf8('thevault/approval/sas/v1'),
      _utf8(approvalId),
      newDevicePublicKey,
      approverPublicKey,
      approverNonce,
      newDeviceNonce,
    ]);
    final v = ByteData.sublistView(h, 0, 4).getUint32(0, Endian.big) % 1000000;
    return v.toString().padLeft(6, '0');
  }

  /// Encrypts the vault key for the new device (authenticated with the approver's ephemeral key).
  ({Uint8List box, Uint8List nonce}) sealVaultKey({
    required SecureKey vaultKey,
    required String userId,
    required String approvalId,
    required Uint8List newDevicePublicKey,
    required SecureKey approverSecretKey,
  }) {
    final nonce = randomBytes(sodium.crypto.box.nonceBytes);
    final payload = vaultKey.runUnlockedSync((vk) => _utf8(jsonEncode({
          'vk': base64Url.encode(vk),
          'userId': userId,
          'approvalId': approvalId,
        })));
    final box = sodium.crypto.box.easy(
      message: payload,
      nonce: nonce,
      publicKey: newDevicePublicKey,
      secretKey: approverSecretKey,
    );
    payload.fillRange(0, payload.length, 0);
    return (box: box, nonce: nonce);
  }

  /// Opens the vault key sent by the approver. Throws [CryptoException] if anything does not match.
  SecureKey openVaultKey({
    required Uint8List box,
    required Uint8List nonce,
    required Uint8List approverPublicKey,
    required SecureKey deviceSecretKey,
    required String userId,
    required String approvalId,
  }) {
    final Uint8List plain;
    try {
      plain = sodium.crypto.box.openEasy(
        cipherText: box,
        nonce: nonce,
        publicKey: approverPublicKey,
        secretKey: deviceSecretKey,
      );
    } on SodiumException {
      throw CryptoException('approval box authentication failed');
    }
    try {
      final m = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      if (m['userId'] != userId || m['approvalId'] != approvalId) {
        throw CryptoException('approval box does not belong to this request');
      }
      final vk = base64Url.decode(m['vk'] as String);
      final key = keyFromBytes(Uint8List.fromList(vk));
      vk.fillRange(0, vk.length, 0);
      return key;
    } on FormatException {
      throw CryptoException('malformed approval box');
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  // ------------------------------------------------------------------ PIN

  /// Argon2id hash string of the PIN (computed in a background isolate).
  static Future<String> hashPin(String pin) => Isolate.run(() async {
        final s = await SodiumSumoInit.init();
        return s.crypto.pwhash.str(
          password: pin,
          opsLimit: s.crypto.pwhash.opsLimitInteractive,
          memLimit: s.crypto.pwhash.memLimitInteractive,
        );
      });

  static Future<bool> verifyPin(String hash, String pin) => Isolate.run(() async {
        final s = await SodiumSumoInit.init();
        return s.crypto.pwhash.strVerify(passwordHash: hash, password: pin);
      });

  // ----------------------------------------------------------- backup files

  /// Key for an exported backup file, derived from its password (in a background isolate).
  static Future<Uint8List> backupKey(String password, Uint8List salt, int ops, int mem) =>
      Isolate.run(() async {
        final s = await SodiumSumoInit.init();
        final k = s.crypto.pwhash.callStr(
          outLen: 32,
          password: password,
          salt: salt,
          opsLimit: ops,
          memLimit: mem,
          alg: CryptoPwhashAlgorithm.argon2id13,
        );
        final out = k.extractBytes();
        k.dispose();
        return out;
      });
}
