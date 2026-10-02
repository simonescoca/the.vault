import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/crypto/password_generator.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/model/item_draft.dart';
import 'package:the_vault/src/core/model/text_utils.dart';

void main() {
  var n = 0;
  String fid() => 'f${n++}';
  final now = DateTime(2026, 10, 2, 12);

  Item ok(SaveOutcome o) => (o as SaveOk).item;

  group('save rules (SPEC §6.3)', () {
    test('a new entry starts with three empty rows with suggested keys', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid);
      expect(d.fields.map((f) => f.suggestion), ['sito web', 'email', 'password']);
      expect(d.fields.every((f) => f.key.isEmpty && f.value.isEmpty), isTrue);
      expect(d.isNew, isTrue);
    });

    test('value only → the suggestion becomes the key; key only → row removed; empty rows removed', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid)..title = ' Netflix ';
      d.fields[0].value = 'netflix.com';
      d.fields[1].key = 'email'; // key without value
      d.fields[2].value = 's3cret';
      final extra = d.addRow()..value = 'note libere'; // added row: no suggestion
      final blank = d.addRow();
      expect(blank.isBlank, isTrue);
      final item = ok(d.build(id: 'id-1', now: now));
      expect(item.title, 'Netflix');
      expect(item.fields.map((f) => [f.key, f.value]).toList(), [
        ['sito web', 'netflix.com'],
        ['password', 's3cret'],
        ['', 'note libere'],
      ]);
      expect(item.fields.last.id, extra.id);
      expect(item.created, now);
    });

    test('whitespace-only values count as empty, other values are kept as typed', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid)..title = 'X';
      d.fields[0].value = '   ';
      d.fields[1].value = '  spazi ai lati  ';
      final item = ok(d.build(id: 'id', now: now));
      expect(item.fields.single.value, '  spazi ai lati  ');
      expect(item.fields.single.key, 'email');
    });

    test('an entry can end up with no rows; editing shows one empty row again', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid)
        ..title = 'Solo descrizione'
        ..description = '  Appunti  ';
      final item = ok(d.build(id: 'id', now: now));
      expect(item.fields, isEmpty);
      expect(item.description, 'Appunti');
      final edit = ItemDraft.fromItem(item, fid);
      expect(edit.fields, hasLength(1));
      expect(edit.canRemoveRow, isFalse);
      expect(edit.removeRow(edit.fields.single.id), isFalse, reason: 'at least one row stays');
    });

    test('empty title uses the site name, otherwise the save is refused', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid);
      d.fields[0].value = 'https://www.netflix.com/browse';
      expect(d.titleSuggestion, 'Netflix');
      expect(ok(d.build(id: 'id', now: now)).title, 'Netflix');

      final d2 = ItemDraft.blank(['sito web', 'email', 'password'], fid);
      d2.fields[1].value = 'me@icloud.com';
      expect(d2.build(id: 'id', now: now), isA<SaveNeedsTitle>());

      final d3 = ItemDraft.blank(['website', 'email', 'password'], fid);
      d3.fields[1].value = 'Area clienti';
      d3.fields[1].link = 'mybank.it/login';
      expect(ok(d3.build(id: 'id', now: now)).title, 'Mybank');
    });

    test('links are normalized; invalid links are dropped; hidden and link follow their row', () {
      final d = ItemDraft.blank(['sito web', 'email', 'password'], fid)..title = 'Banca';
      d.fields[0]
        ..value = 'Area clienti'
        ..link = 'bank.it/login';
      d.fields[1]
        ..value = 'testo'
        ..link = 'non è un link';
      d.fields[2]
        ..value = 'pw'
        ..hidden = true;
      d.moveRow(2, 0); // password to the top
      final item = ok(d.build(id: 'id', now: now));
      expect(item.fields[0].value, 'pw');
      expect(item.fields[0].hidden, isTrue);
      expect(item.fields[1].link, 'https://bank.it/login');
      expect(item.fields[2].link, isNull);
    });

    test('row reordering semantics', () {
      final d = ItemDraft.blank(['a', 'b', 'c'], fid);
      final ids = d.fields.map((f) => f.id).toList();
      d.moveRow(0, 3);
      expect(d.fields.map((f) => f.id), [ids[1], ids[2], ids[0]]);
      d.moveRow(2, 0);
      expect(d.fields.map((f) => f.id), ids);
    });

    test('editing keeps id, created, favorite, trash state and unknown fields', () {
      final orig = Item(
          id: 'x',
          title: 'T',
          fields: const [Field(id: 'a', key: 'k', value: 'v')],
          favorite: true,
          created: DateTime(2020),
          updated: DateTime(2020),
          extra: const {'future': 1});
      final d = ItemDraft.fromItem(orig, fid)..title = 'T2';
      final item = ok(d.build(id: 'ignored', now: now));
      expect(item.id, 'x');
      expect(item.created, DateTime(2020));
      expect(item.updated, now);
      expect(item.favorite, isTrue);
      expect(item.toJson()['future'], 1);
    });
  });

  group('JSON', () {
    test('round-trip and compact encoding', () {
      final item = Item(
        id: 'id',
        title: 'Netflix',
        fields: const [
          Field(id: 'a', key: 'sito web', value: 'netflix.com'),
          Field(id: 'b', key: 'password', value: 'pw', hidden: true),
          Field(id: 'c', key: 'area', value: 'Area clienti', link: 'https://netflix.com/account'),
        ],
        description: 'Famiglia',
        favorite: true,
        trashedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        created: DateTime.fromMillisecondsSinceEpoch(1600000000000),
        updated: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final back = Item.decode('id', item.encode());
      expect(back.sameContent(item), isTrue);
      expect(back.fields[1].hidden, isTrue);
      expect(back.fields[2].link, 'https://netflix.com/account');
      expect(item.toJson()['fields'][0].containsKey('h'), isFalse);
    });
  });

  group('text helpers', () {
    test('URLs, bare domains and emails', () {
      expect(detectUrl('https://example.com/x')?.toString(), 'https://example.com/x');
      expect(detectUrl('www.netflix.com')?.toString(), 'https://www.netflix.com');
      expect(detectUrl('netflix.com')?.host, 'netflix.com');
      expect(detectUrl('banca.it/login')?.path, '/login');
      expect(detectUrl('me@icloud.com'), isNull, reason: 'emails are never links');
      expect(detectUrl('README.md'), isNull);
      expect(detectUrl('script.sh'), isNull);
      expect(detectUrl('README.md', key: 'sito web'), isNotNull, reason: 'a website key accepts any TLD');
      expect(detectUrl('ciao mondo.com'), isNull);
      expect(detectUrl('1.5'), isNull);
      expect(detectUrl('s3cr3t.Pass'), isNull);
      expect(isEmail('mario.rossi@icloud.com'), isTrue);
      expect(isEmail('not an email'), isFalse);
      expect(normalizeLink('example.org'), 'https://example.org');
      expect(normalizeLink('ftp://x.org'), isNull);
      expect(normalizeLink('nope'), isNull);
    });

    test('site names', () {
      expect(siteName(Uri.parse('https://www.netflix.com/browse')), 'Netflix');
      expect(siteName(Uri.parse('https://mail.google.co.uk')), 'Google');
      expect(siteName(Uri.parse('https://intesasanpaolo.com')), 'Intesasanpaolo');
    });

    test('search and sorting ignore case and accents', () {
      Item it(String title, {List<Field> fields = const [], String desc = ''}) =>
          Item(id: title, title: title, fields: fields, description: desc, created: now, updated: now);
      final a = it('Università', fields: const [Field(id: '1', key: 'utente', value: 'mario'), Field(id: '2', key: 'pin', value: '4821', hidden: true)]);
      expect(a.matchScore('UNIVERS'), 2);
      expect(a.matchScore('universita'), 2);
      expect(a.matchScore('mario'), 1);
      expect(a.matchScore('4821'), 0, reason: 'hidden values are not searchable');
      expect(a.matchScore('pin'), 1, reason: 'keys are searchable');
      expect(a.subtitle, 'mario');
      final list = [it('banca'), it('Amazon'), it('Èlite'), it('apple')]..sort(compareItems);
      expect(list.map((i) => i.title), ['Amazon', 'apple', 'banca', 'Èlite']);
    });
  });

  test('password generator', () async {
    final c = await VaultCrypto.init();
    final g = PasswordGenerator(c.sodium);
    for (var i = 0; i < 50; i++) {
      final p = g.generate(const PasswordOptions(length: 12));
      expect(p, hasLength(12));
      expect(p, contains(RegExp('[A-Z]')));
      expect(p, contains(RegExp('[a-z]')));
      expect(p, contains(RegExp('[0-9]')));
      expect(p.split('').any(PasswordGenerator.symbolChars.contains), isTrue);
    }
    final digits = g.generate(const PasswordOptions(length: 8, upper: false, lower: false, symbols: false));
    expect(RegExp(r'^\d{8}$').hasMatch(digits), isTrue);
    expect(g.generate(const PasswordOptions(length: 500)), hasLength(64));
    expect(g.generate(const PasswordOptions(length: 2)), hasLength(8));
    final seen = {for (var i = 0; i < 20; i++) g.generate(const PasswordOptions())};
    expect(seen, hasLength(20));
  });
}
