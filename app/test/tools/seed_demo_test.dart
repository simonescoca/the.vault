// Development tool (skipped unless THEVAULT_SEED_DIR is set): creates a demo vault on a running
// server so the real app can be launched on it, e.g. for screenshots.
//
//   THEVAULT_SEED_DIR=/tmp/demo THEVAULT_SEED_SERVER=http://127.0.0.1:8743 \
//   THEVAULT_SEED_MAILLOG=/path/to/mail.log flutter test test/tools/seed_demo_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/app/lock_service.dart';
import 'package:the_vault/src/app/platform_services.dart';
import 'package:the_vault/src/core/account/account_service.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/session.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

class _NoPlatform implements PlatformServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final dir = Platform.environment['THEVAULT_SEED_DIR'];
  test('seed demo vault', () async {
    final server = Platform.environment['THEVAULT_SEED_SERVER']!;
    final mailLog = Platform.environment['THEVAULT_SEED_MAILLOG']!;
    final email = Platform.environment['THEVAULT_SEED_EMAIL'] ?? 'mario.rossi@icloud.com';
    await Directory(dir!).create(recursive: true);
    final crypto = await VaultCrypto.init();
    final secrets = FileSecretStore('$dir/dev-secrets.json');
    final account = AccountService(crypto: crypto, secrets: secrets);
    final url = await account.checkServer(server);
    await account.requestCode(url, email, deviceName: 'MacBook di Mario');
    final codes = RegExp(r'(\d{3}) (\d{3})').allMatches(File(mailLog).readAsStringSync()).toList();
    final code = '${codes.last.group(1)}${codes.last.group(2)}';
    final id = await account.verifyCode(server: url, email: email, code: code, deviceName: 'MacBook di Mario', platform: 'macos');
    final vault = await account.createVault(id);
    File('$dir/recovery-code.txt').writeAsStringSync(vault.code.formatted);
    await LockService(secrets, _NoPlatform()).setPin('123456');

    final s = Session.open(identity: id, dataDir: dir, crypto: crypto);
    s.vault.unlock(vault.vaultKey);
    var n = 0;
    Item item(String title, List<(String, String, {bool hidden, String? link})> rows, {String desc = '', bool fav = false}) => Item(
          id: VaultController.newId(),
          title: title,
          fields: [for (final r in rows) Field(id: 'f${n++}', key: r.$1, value: r.$2, hidden: r.hidden, link: r.link)],
          description: desc,
          favorite: fav,
          created: DateTime.now(),
          updated: DateTime.now(),
        );
    final items = [
      item('Netflix', [
        ('sito web', 'netflix.com', hidden: false, link: null),
        ('email', email, hidden: false, link: null),
        ('password', 'Tr4m0nt0-Rosso!', hidden: true, link: null),
        ('profilo', 'Mario', hidden: false, link: null),
      ], desc: 'Account di famiglia, condiviso con Giulia. Rinnovo a marzo.', fav: true),
      item('Intesa Sanpaolo', [
        ('area clienti', 'Area clienti', hidden: false, link: 'https://www.intesasanpaolo.com'),
        ('codice titolare', '48 211 905', hidden: false, link: null),
        ('PIN', '73914', hidden: true, link: null),
        ('IBAN', 'IT60 X054 2811 1010 0000 0123 456', hidden: false, link: null),
      ], fav: true),
      item('Amazon', [
        ('sito web', 'amazon.it', hidden: false, link: null),
        ('email', email, hidden: false, link: null),
        ('password', 'q8!Kp2#vL0m', hidden: false, link: null),
      ]),
      item('Wi-Fi di casa', [
        ('rete', 'Casa-5G', hidden: false, link: null),
        ('password', 'casa-bella-2024', hidden: false, link: null),
        ('router', '192.168.1.1', hidden: false, link: null),
      ], desc: 'Router in soggiorno, dietro la TV.'),
      item('Apple ID', [
        ('sito web', 'account.apple.com', hidden: false, link: null),
        ('email', email, hidden: false, link: null),
        ('password', 'M3la-Verde-77', hidden: true, link: null),
        ('codici di recupero', 'K7QM-3XRP-9HTV-2WQD', hidden: true, link: null),
      ]),
      item('Spotify', [
        ('email', email, hidden: false, link: null),
        ('password', 'mus1ca!Sempre', hidden: true, link: null),
      ]),
      item('Agenzia delle Entrate', [
        ('sito web', 'agenziaentrate.gov.it', hidden: false, link: null),
        ('codice fiscale', 'RSSMRA80A01H501U', hidden: false, link: null),
        ('PIN Fisconline', '4417 2210', hidden: true, link: null),
      ]),
      item('GitHub', [
        ('sito web', 'github.com', hidden: false, link: null),
        ('utente', 'mariorossi', hidden: false, link: null),
        ('password', 'g1t-Hub_2026', hidden: true, link: null),
      ]),
    ];
    for (final i in items) {
      s.vault.save(i);
    }
    final old = item('Vecchio forum', [('utente', 'simo85', hidden: false, link: null)]);
    s.vault.save(old);
    s.vault.moveToTrash(old.id);
    await s.sync.sync();
    expect(s.db.pendingCount, 0);
    await s.close();
  }, skip: dir == null ? 'development tool' : null, timeout: const Timeout(Duration(minutes: 2)));
}
