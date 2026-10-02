import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/crypto/file_crypto.dart';
import 'package:the_vault/src/core/crypto/recovery_code.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';

void main() {
  late VaultCrypto c;
  setUpAll(() async => c = await VaultCrypto.init());

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('records', () {
    test('round-trip, padding hides the exact length, AAD binds the id', () {
      final vk = c.newVaultKey();
      final k = c.itemsKey(vk);
      const id = '11111111-1111-4111-8111-111111111111';
      final ct = c.encryptRecord(k, id, bytes('{"title":"Netflix"}'));
      expect(ct[0], 1);
      expect(ct.length, 1 + 24 + 256 + 16, reason: 'padded to 256 bytes');
      expect(utf8.decode(c.decryptRecord(k, id, ct)), '{"title":"Netflix"}');
      // Same plaintext encrypts differently every time (random nonce).
      expect(c.encryptRecord(k, id, bytes('x')), isNot(equals(c.encryptRecord(k, id, bytes('x')))));
      // Moving the ciphertext to another record id is detected.
      expect(() => c.decryptRecord(k, '22222222-2222-4222-8222-222222222222', ct), throwsA(isA<CryptoException>()));
      // Tampering is detected.
      final bad = Uint8List.fromList(ct)..[40] ^= 1;
      expect(() => c.decryptRecord(k, id, bad), throwsA(isA<CryptoException>()));
      // Another vault key cannot read it.
      expect(() => c.decryptRecord(c.itemsKey(c.newVaultKey()), id, ct), throwsA(isA<CryptoException>()));
    });

    test('key check is deterministic per vault key', () {
      final vk = c.newVaultKey();
      final copy = c.keyFromBytes(vk.extractBytes());
      expect(c.keyCheck(vk), c.keyCheck(copy));
      expect(c.keyCheck(vk), hasLength(16));
      expect(c.keyCheck(vk), isNot(equals(c.keyCheck(c.newVaultKey()))));
    });
  });

  group('emergency code', () {
    test('format and parsing', () {
      final code = RecoveryCode.random(c.randomBytes(15));
      expect(code.compact, hasLength(24));
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}$').hasMatch(code.formatted), isTrue);
      expect(RecoveryCode.tryParse(code.formatted)!.bytes, code.bytes);
      expect(RecoveryCode.tryParse(code.compact.toLowerCase())!.bytes, code.bytes);
      final spaced = code.formatted.replaceAll('-', ' ');
      expect(RecoveryCode.tryParse(' $spaced ')!.bytes, code.bytes);
      expect(RecoveryCode.tryParse('ABCD-EFGH'), isNull);
      expect(RecoveryCode.tryParse('${code.compact.substring(0, 23)}U'), isNull, reason: 'U is not in the alphabet');
      // Look-alikes: O→0, I/L→1.
      final zero = RecoveryCode.random(Uint8List(15));
      expect(zero.compact, '0' * 24);
      expect(RecoveryCode.tryParse('O' * 24)!.bytes, Uint8List(15));
      expect(code.toString(), isNot(contains(code.compact)), reason: 'never log the code');
    });

    test('wrap and unwrap the vault key; wrong code or user fails', () async {
      final vk = c.newVaultKey();
      const user = 'u-1';
      final rec = await c.createRecovery(vk, user);
      expect(rec.bundle.wrap, hasLength(72));
      expect(rec.authKey, hasLength(32));
      final opened = await c.openRecovery(rec.bundle, RecoveryCode.tryParse(rec.code.formatted)!, user);
      expect(opened.vaultKey.extractBytes(), vk.extractBytes());
      expect(opened.authKey, rec.authKey);
      final wrong = RecoveryCode.random(c.randomBytes(15));
      expect(c.openRecovery(rec.bundle, wrong, user), throwsA(isA<CryptoException>()));
      expect(c.openRecovery(rec.bundle, rec.code, 'other-user'), throwsA(isA<CryptoException>()));
    });
  });

  group('device approval', () {
    test('commitment, matching codes and authenticated key delivery', () {
      final newDevice = c.newBoxKeyPair();
      final approver = c.newBoxKeyPair();
      final n1 = c.randomBytes(32), n2 = c.randomBytes(32);
      const approvalId = '33333333-3333-4333-8333-333333333333';
      final commit = c.approvalCommitment(newDevice.publicKey, n2);
      expect(commit, hasLength(32));
      expect(c.approvalCommitment(newDevice.publicKey, n2), commit);
      expect(c.approvalCommitment(newDevice.publicKey, c.randomBytes(32)), isNot(equals(commit)));

      String code(Uint8List pk2, Uint8List pk1, Uint8List a, Uint8List b) => c.approvalCode(
          approvalId: approvalId, newDevicePublicKey: pk2, approverPublicKey: pk1, approverNonce: a, newDeviceNonce: b);
      final onNew = code(newDevice.publicKey, approver.publicKey, n1, n2);
      final onApprover = code(newDevice.publicKey, approver.publicKey, n1, n2);
      expect(onNew, onApprover);
      expect(RegExp(r'^\d{6}$').hasMatch(onNew), isTrue);
      // A substituted key gives (almost surely) a different code.
      final evil = c.newBoxKeyPair();
      expect(code(evil.publicKey, approver.publicKey, n1, n2), isNot(onNew));

      final vk = c.newVaultKey();
      final sealed = c.sealVaultKey(
          vaultKey: vk,
          userId: 'u-1',
          approvalId: approvalId,
          newDevicePublicKey: newDevice.publicKey,
          approverSecretKey: approver.secretKey);
      final got = c.openVaultKey(
          box: sealed.box,
          nonce: sealed.nonce,
          approverPublicKey: approver.publicKey,
          deviceSecretKey: newDevice.secretKey,
          userId: 'u-1',
          approvalId: approvalId);
      expect(got.extractBytes(), vk.extractBytes());
      // A box from an impostor (not the key covered by the code) is rejected.
      expect(
          () => c.openVaultKey(
              box: sealed.box,
              nonce: sealed.nonce,
              approverPublicKey: evil.publicKey,
              deviceSecretKey: newDevice.secretKey,
              userId: 'u-1',
              approvalId: approvalId),
          throwsA(isA<CryptoException>()));
      // A box for another request is rejected.
      expect(
          () => c.openVaultKey(
              box: sealed.box,
              nonce: sealed.nonce,
              approverPublicKey: approver.publicKey,
              deviceSecretKey: newDevice.secretKey,
              userId: 'u-1',
              approvalId: 'other'),
          throwsA(isA<CryptoException>()));
    });
  });

  test('PIN hashing', () async {
    final h = await VaultCrypto.hashPin('123456');
    expect(h, startsWith(r'$argon2id$'));
    expect(await VaultCrypto.verifyPin(h, '123456'), isTrue);
    expect(await VaultCrypto.verifyPin(h, '123457'), isFalse);
  });

  group('attachments', () {
    final sizes = [0, 1, 1000, FileCrypto.chunkSize - 1, FileCrypto.chunkSize, FileCrypto.chunkSize + 1, 3 * FileCrypto.chunkSize];
    for (final size in sizes) {
      test('round-trip of $size bytes, exact encrypted size, truncation rejected', () async {
        final data = c.randomBytes(size);
        final key = FileCrypto.newKey(c);
        final enc = await FileCrypto.encryptBytes(c.sodium, data, key);
        expect(enc.length, FileCrypto.encryptedSize(size));
        expect(await FileCrypto.decryptBytes(c.sodium, enc, key), data);
        if (enc.length > 24 + 17) {
          final truncated = Uint8List.sublistView(enc, 0, enc.length - 17);
          expect(FileCrypto.decryptBytes(c.sodium, truncated, key), throwsA(isA<CryptoException>()));
        }
        expect(FileCrypto.decryptBytes(c.sodium, enc, FileCrypto.newKey(c)), throwsA(isA<CryptoException>()));
      });
    }

    test('files on disk (background isolate)', () async {
      final dir = await Directory.systemTemp.createTemp('tv');
      addTearDown(() => dir.delete(recursive: true));
      final src = File('${dir.path}/doc.pdf')..writeAsBytesSync(c.randomBytes(200000));
      final key = FileCrypto.newKey(c);
      await FileCrypto.encryptFile(src.path, '${dir.path}/doc.enc', key);
      expect(File('${dir.path}/doc.enc').lengthSync(), FileCrypto.encryptedSize(200000));
      await FileCrypto.decryptFile('${dir.path}/doc.enc', '${dir.path}/doc.out', key);
      expect(File('${dir.path}/doc.out').readAsBytesSync(), src.readAsBytesSync());
      await expectLater(FileCrypto.decryptFile('${dir.path}/doc.enc', '${dir.path}/bad.out', FileCrypto.newKey(c)),
          throwsA(isA<CryptoException>()));
      expect(File('${dir.path}/bad.out').existsSync(), isFalse);
      expect(File('${dir.path}/bad.out.tmp').existsSync(), isFalse);
    });
  });
}
