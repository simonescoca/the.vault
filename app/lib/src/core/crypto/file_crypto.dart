// Attachment encryption: libsodium secretstream (XChaCha20-Poly1305), 64 KiB chunks.
// Layout: header(24) ‖ chunk₁ ‖ … ‖ chunk_n, each chunk = plaintext + 17 bytes; the stream always
// ends with a FINAL-tagged chunk, so a truncated file is rejected.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'vault_crypto.dart';

class FileCrypto {
  static const chunkSize = 64 * 1024;

  /// Size of the encrypted file for a plaintext of [plainSize] bytes.
  static int encryptedSize(int plainSize) {
    const header = 24;
    const abytes = 17;
    final fullChunks = plainSize ~/ chunkSize;
    final rest = plainSize % chunkSize;
    // A final empty chunk is added when the size is a multiple of the chunk size.
    final chunks = fullChunks + 1;
    return header + fullChunks * chunkSize + rest + chunks * abytes;
  }

  /// A new random file key (32 bytes).
  static Uint8List newKey(VaultCrypto c) => c.randomBytes(32);

  /// Encrypts the file at [src] into [dst]. Runs in a background isolate.
  static Future<void> encryptFile(String src, String dst, Uint8List key) => Isolate.run(() async {
        final s = await SodiumSumoInit.init();
        final k = SecureKey.fromList(s, key);
        final tmp = File('$dst.tmp');
        final sink = tmp.openWrite();
        try {
          await sink.addStream(s.crypto.secretStream.pushChunked(
            messageStream: File(src).openRead(),
            key: k,
            chunkSize: chunkSize,
          ));
          await sink.close();
          await tmp.rename(dst);
        } catch (_) {
          await sink.close().catchError((_) {});
          if (await tmp.exists()) await tmp.delete();
          rethrow;
        } finally {
          k.dispose();
        }
      });

  /// Decrypts [src] into [dst]. Throws if the file is corrupted, truncated or the key is wrong.
  static Future<void> decryptFile(String src, String dst, Uint8List key) => Isolate.run(() async {
        final s = await SodiumSumoInit.init();
        final k = SecureKey.fromList(s, key);
        final tmp = File('$dst.tmp');
        final sink = tmp.openWrite();
        try {
          await sink.addStream(s.crypto.secretStream.pullChunked(
            cipherStream: File(src).openRead(),
            key: k,
            chunkSize: chunkSize,
          ));
          await sink.close();
          await tmp.rename(dst);
        } catch (e) {
          await sink.close().catchError((_) {});
          if (await tmp.exists()) await tmp.delete();
          throw CryptoException('attachment could not be decrypted: $e');
        } finally {
          k.dispose();
        }
      });

  /// In-memory variants (small data, tests).
  static Future<Uint8List> encryptBytes(SodiumSumo s, Uint8List data, Uint8List key) async {
    final k = SecureKey.fromList(s, key);
    try {
      final b = BytesBuilder(copy: false);
      await for (final c in s.crypto.secretStream.pushChunked(
        messageStream: Stream.value(data),
        key: k,
        chunkSize: chunkSize,
      )) {
        b.add(c);
      }
      return b.toBytes();
    } finally {
      k.dispose();
    }
  }

  static Future<Uint8List> decryptBytes(SodiumSumo s, Uint8List data, Uint8List key) async {
    final k = SecureKey.fromList(s, key);
    try {
      final b = BytesBuilder(copy: false);
      await for (final c in s.crypto.secretStream.pullChunked(
        cipherStream: Stream.value(data),
        key: k,
        chunkSize: chunkSize,
      )) {
        b.add(c);
      }
      return b.toBytes();
    } catch (e) {
      throw CryptoException('attachment could not be decrypted: $e');
    } finally {
      k.dispose();
    }
  }
}
