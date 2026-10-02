// Verifies that the native building blocks (libsodium, SQLite) build and load
// on the current platform. Runs in CI on every push.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('libsodium loads: XChaCha20-Poly1305 round-trip and Argon2id', () async {
    final sodium = await SodiumSumoInit.init();
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final key = aead.keygen();
    final nonce = sodium.randombytes.buf(aead.nonceBytes);
    final msg = Uint8List.fromList(utf8.encode('ciao vault'));
    final ct = aead.encrypt(message: msg, nonce: nonce, key: key);
    final pt = aead.decrypt(cipherText: ct, nonce: nonce, key: key);
    expect(utf8.decode(pt), 'ciao vault');

    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final derived = sodium.crypto.pwhash.callStr(
      outLen: 32,
      password: 'pw',
      salt: salt,
      opsLimit: sodium.crypto.pwhash.opsLimitInteractive,
      memLimit: sodium.crypto.pwhash.memLimitInteractive,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
    expect(derived.length, 32);
    expect(sodium.version.toString(), startsWith('1.0.'));
  });

  test('sqlite3 opens an in-memory database', () {
    final db = sqlite3.openInMemory();
    db.execute('create table t(x text)');
    db.execute("insert into t values ('ok')");
    expect(db.select('select x from t').first['x'], 'ok');
    db.close();
  });
}
