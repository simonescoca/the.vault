// Export → import between vaults when attachments are shared or could not be exported.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/backup/backup_service.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/storage/local_db.dart';
import 'package:the_vault/src/core/sync/sync_engine.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

/// A vault on this device whose server no longer recognizes it: nothing can be downloaded.
class LocalVault {
  LocalVault(VaultCrypto crypto, this.dir, DateTime Function() clock) {
    final sync = SyncEngine(
      db: db,
      api: ApiClient(
        base: Uri.parse('https://vault.example.ts.net'),
        token: 'tok',
        client: MockClient((_) async => http.Response('{"error":{"code":"device_unknown","message":""}}', 401)),
      ),
      blobs: BlobFiles('${dir.path}/blobs'),
      onConflict: (_, _, _) async => false,
    )..enabled = false;
    vault = VaultController(crypto: crypto, db: db, sync: sync, clock: clock)..unlock(crypto.newVaultKey());
  }

  final db = LocalDb.memory();
  final Directory dir;
  late final VaultController vault;

  Future<void> close() async {
    vault.dispose();
    await vault.sync.dispose();
    db.close();
  }
}

Item entry(String id, String title, {List<Attachment> files = const []}) => Item(
      id: id,
      title: title,
      fields: [Field(id: 'f0', key: 'nota', value: title)],
      files: files,
      created: DateTime(2026, 1, 1),
      updated: DateTime(2026, 1, 1),
    );

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  var now = DateTime(2026, 5, 1);
  final vaults = <LocalVault>[];
  const password = 'una password lunga';

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() async => dir = await Directory.systemTemp.createTemp('tv-merge'));
  tearDown(() async {
    for (final v in vaults) {
      await v.close();
    }
    vaults.clear();
    await dir.delete(recursive: true);
  });

  LocalVault newVault(String name) {
    final v = LocalVault(crypto, Directory('${dir.path}/$name')..createSync(), () => now);
    vaults.add(v);
    return v;
  }

  File sample(String name, int size) => File('${dir.path}/$name')..writeAsBytesSync(List.generate(size, (i) => (i * 7) % 251));

  test('entries sharing one attachment (conflict copies): exported once, imported for both', () async {
    final a = newVault('a');
    final src = sample('contratto.pdf', 3000);
    final shared = await a.vault.addAttachment(src);
    a.vault.save(entry('11111111-1111-4111-8111-111111111111', 'Casa', files: [shared]));
    a.vault.save(entry('22222222-2222-4222-8222-222222222222', 'Casa (conflitto)', files: [shared]));

    final file = '${dir.path}/backup.thevault';
    final out = await BackupService(crypto).export(a.vault, file, password);
    expect((out.items, out.files, out.missing), (2, 1, 0));

    final b = newVault('b');
    expect(await BackupService(crypto).import(b.vault, file, password, dir.path), 2);
    final restored = b.vault.list(Section.all);
    expect(restored, hasLength(2));
    final ids = {for (final i in restored) i.files.single.id};
    expect(ids, hasLength(1), reason: 'still one blob shared by both entries');
    for (final i in restored) {
      final copy = await b.vault.exportAttachment(i.files.single, '${dir.path}/out-${i.id}');
      expect(copy.readAsBytesSync(), src.readAsBytesSync());
    }
  });

  test('an attachment left out of the export does not replace the copy this vault still has', () async {
    final src = sample('foto.jpg', 2000);
    const id = '33333333-3333-4333-8333-333333333333';
    // This vault (e.g. linked again to the restored server): the entry with its attachment.
    final b = newVault('b');
    final att = await b.vault.addAttachment(src);
    b.vault.save(entry(id, 'Auto', files: [att]));

    // The exporting device has a newer edit of the entry but never downloaded the attachment.
    now = now.add(const Duration(days: 1));
    final a = newVault('a');
    a.vault.save(entry(id, 'Auto (modificata)', files: [att]));
    final file = '${dir.path}/backup.thevault';
    final out = await BackupService(crypto).export(a.vault, file, password);
    expect((out.files, out.missing), (0, 1));

    now = now.add(const Duration(days: 1));
    expect(await BackupService(crypto).import(b.vault, file, password, dir.path), 1);
    final merged = b.vault.byId(id)!;
    expect(merged.title, 'Auto (modificata)', reason: 'the newer entry wins');
    expect(merged.files.map((f) => f.id), [att.id], reason: 'with the attachment this vault still has');
    final copy = await b.vault.exportAttachment(merged.files.single, '${dir.path}/out');
    expect(copy.readAsBytesSync(), src.readAsBytesSync());
  });
}
