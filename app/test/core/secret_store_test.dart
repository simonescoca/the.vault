import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/app/settings.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';

void main() {
  group('BundledSecretStore', () {
    test('keeps every secret in one entry of the system store', () async {
      final inner = MemorySecretStore();
      final s = BundledSecretStore(inner);
      await s.write('a', '1');
      await s.write('b', '2');
      expect(await s.read('a'), '1');
      expect(await s.read('b'), '2');
      expect(await s.read('c'), isNull);
      expect(inner.values.keys, ['secrets'], reason: 'one keychain entry → one permission question after an update');
      await s.delete('a');
      expect(await s.read('a'), isNull);
      await s.delete('b');
      expect(inner.values, isEmpty, reason: 'the entry disappears with the last secret');
    });

    test('writes started together are all kept', () async {
      final s = BundledSecretStore(MemorySecretStore());
      await Future.wait([for (var i = 0; i < 20; i++) s.write('k$i', 'v$i')]);
      for (var i = 0; i < 20; i++) {
        expect(await s.read('k$i'), 'v$i');
      }
    });

    test('deleteAll and a damaged entry', () async {
      final inner = MemorySecretStore();
      final s = BundledSecretStore(inner);
      await s.write('a', '1');
      await s.deleteAll();
      expect(inner.values, isEmpty);
      inner.values['secrets'] = '{not json';
      expect(await s.read('a'), isNull);
      await s.write('a', '2');
      expect(await s.read('a'), '2');
    });
  });

  group('visibleWindowBounds', () {
    const main = Rect.fromLTWH(0, 0, 1440, 900);
    const right = Rect.fromLTWH(1440, 0, 1920, 1080);

    test('keeps a window that is on a screen', () {
      const w = Rect.fromLTWH(100, 80, 1180, 760);
      expect(visibleWindowBounds(w, [main]), w);
      const onRight = Rect.fromLTWH(1600, 100, 1180, 760);
      expect(visibleWindowBounds(onRight, [main, right]), onRight);
    });

    test('forgets a window whose screen is gone or that is barely visible', () {
      expect(visibleWindowBounds(const Rect.fromLTWH(1600, 100, 1180, 760), [main]), isNull);
      expect(visibleWindowBounds(const Rect.fromLTWH(1400, 100, 1180, 760), [main]), isNull, reason: 'only 40 px visible');
      expect(visibleWindowBounds(const Rect.fromLTWH(-5000, -5000, 1180, 760), [main, right]), isNull);
      expect(visibleWindowBounds(null, [main]), isNull);
      expect(visibleWindowBounds(const Rect.fromLTWH(100, 100, 1180, 760), []), isNull);
    });
  });
}
