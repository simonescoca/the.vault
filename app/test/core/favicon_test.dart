import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/favicon/favicon_service.dart';
import 'package:the_vault/src/core/storage/local_db.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

/// CRC-32 of PNG chunks.
int _crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xffffffff;
}

Uint8List _png(int side) => Uint8List.fromList(img.encodePng(img.Image(width: side, height: side)..clear(img.ColorRgb8(200, 30, 30))));

/// A real small PNG whose header claims [w]×[h] pixels (a "decompression bomb").
Uint8List _pngClaiming(int w, int h) {
  final b = _png(16);
  final d = ByteData.sublistView(b);
  d.setUint32(16, w);
  d.setUint32(20, h);
  d.setUint32(29, _crc32(b.sublist(12, 29)));
  return b;
}

/// An .ico with one PNG picture inside.
Uint8List _ico(Uint8List png, {int side = 32}) {
  final out = BytesBuilder();
  final head = ByteData(6 + 16)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 1, Endian.little)
    ..setUint8(6, side == 256 ? 0 : side)
    ..setUint8(7, side == 256 ? 0 : side)
    ..setUint16(10, 1, Endian.little)
    ..setUint16(12, 32, Endian.little)
    ..setUint32(14, png.length, Endian.little)
    ..setUint32(18, 22, Endian.little);
  out.add(head.buffer.asUint8List());
  out.add(png);
  return out.toBytes();
}

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  group('toPng', () {
    test('normal icons are converted', () {
      final a = FaviconService.toPng(_png(180))!;
      expect(img.decodePng(a)!.width, 64);
      expect(FaviconService.toPng(_ico(_png(32)))!.isNotEmpty, isTrue);
    });

    test('files that claim a huge picture are refused before decoding', () {
      expect(FaviconService.toPng(_pngClaiming(20000, 20000)), isNull);
      expect(FaviconService.toPng(_pngClaiming(16, 70000)), isNull);
      expect(FaviconService.toPng(_ico(_pngClaiming(20000, 20000))), isNull);
      expect(FaviconService.toPng(Uint8List.fromList([0, 0, 1, 0, 9, 9, 1, 2, 3, 4])), isNull, reason: 'broken .ico');
    });
  });

  group('cache', () {
    test('names are hashed with the vault key, contents are encrypted and bound to their name', () {
      final k1 = crypto.cacheKey(crypto.newVaultKey());
      final k2 = crypto.cacheKey(crypto.newVaultKey());
      final n = crypto.cacheName(k1, 'favicon', 'netflix.com');
      expect(n, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(crypto.cacheName(k1, 'favicon', 'netflix.com'), n);
      expect(crypto.cacheName(k2, 'favicon', 'netflix.com'), isNot(n));
      expect(crypto.cacheName(k1, 'favicon', 'spotify.com'), isNot(n));
      final sealed = crypto.sealCache(k1, n, _png(16));
      expect(crypto.openCache(k1, n, sealed), _png(16));
      expect(() => crypto.openCache(k1, 'another-name', sealed), throwsA(isA<CryptoException>()));
      expect(() => crypto.openCache(k2, n, sealed), throwsA(isA<CryptoException>()));
    });

    test('the local database shows neither the sites nor their icons', () async {
      final db = LocalDb.memory();
      final key = crypto.newVaultKey();
      final client = MockClient((req) async {
        if (req.url.path == '/') {
          return http.Response('<html><head><link rel="icon" href="/i.png"></head></html>', 200);
        }
        if (req.url.path == '/i.png') return http.Response.bytes(_png(48), 200);
        return http.Response('', 404);
      });
      final service = FaviconService(db, CacheCipher(crypto, crypto.cacheKey(key)), client: client);
      expect(service.icon('netflix.com'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.icon('netflix.com'), isNotNull);

      final names = db.debugFaviconNames();
      expect(names, hasLength(1));
      expect(names.single, isNot(contains('netflix')));
      final stored = db.favicon(names.single)!.data!;
      expect(String.fromCharCodes(stored).contains('PNG'), isFalse, reason: 'icon stored encrypted');

      // The same vault reads it back; another vault key cannot.
      final again = FaviconService(db, CacheCipher(crypto, crypto.cacheKey(key)), enabled: false);
      expect(again.icon('netflix.com'), isNotNull);
      final other = FaviconService(db, CacheCipher(crypto, crypto.cacheKey(crypto.newVaultKey())), enabled: false);
      expect(other.icon('netflix.com'), isNull);
      service.dispose();
      again.dispose();
      other.dispose();
    });
  });
}
