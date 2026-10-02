import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/backup/backup_service.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

import 'harness.dart';

/// The same backup with a different header (the encrypted part is left as it is).
Uint8List _withHeader(Uint8List file, Map<String, dynamic> Function(Map<String, dynamic>) change) {
  final start = BackupService.magic.length;
  final end = file.indexOf(10, start);
  final header = jsonDecode(utf8.decode(file.sublist(start, end))) as Map<String, dynamic>;
  return Uint8List.fromList([...file.sublist(0, start), ...utf8.encode(jsonEncode(change(header))), ...file.sublist(end)]);
}

void main() {
  testWidgets('export file: summary, wrong password, cut or tampered file, import restores entries and attachments', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [
      sampleItem('Banca', [('pin', '4821')]),
      sampleItem('Wi-Fi', [('rete', 'Casa')]),
    ]);
    await tester.runAsync(() async {
      final vault = t.vault;
      final svc = BackupService(t.app.crypto);
      final dir = await Directory.systemTemp.createTemp('tv-backup');
      const password = 'una password lunga';

      final src = File('${dir.path}/contratto.pdf')..writeAsBytesSync(List.generate(200000, (i) => i % 251));
      final banca = vault.list(Section.all).firstWhere((i) => i.title == 'Banca');
      vault.save(banca.copyWith(files: [await vault.addAttachment(src)]));

      final file = '${dir.path}/backup.thevault';
      await svc.export(vault, file, password);
      final summary = await svc.inspect(file, password);
      expect((summary.items, summary.files), (2, 1));
      await expectLater(svc.inspect(file, 'sbagliata'), throwsA(isA<BackupException>()));

      // A file cut short is refused as a whole, never imported halfway.
      final bytes = File(file).readAsBytesSync();
      final cut = File('${dir.path}/cut.thevault')..writeAsBytesSync(bytes.sublist(0, bytes.length - 50));
      await expectLater(svc.import(vault, cut.path, password, dir.path), throwsA(isA<BackupException>()));

      // A header asking for absurd memory is refused before computing anything.
      final greedy = File('${dir.path}/greedy.thevault')..writeAsBytesSync(_withHeader(bytes, (h) => h..['mem'] = 1 << 40));
      await expectLater(svc.inspect(greedy.path, password), throwsA(isA<BackupException>()));

      // After deleting everything for good, the import brings back entries and attachment contents.
      for (final i in vault.list(Section.all)) {
        vault.moveToTrash(i.id);
        vault.deleteForever(i.id);
      }
      expect(vault.list(Section.all), isEmpty);
      expect(await svc.import(vault, file, password, dir.path), 2);
      final restored = vault.list(Section.all).firstWhere((i) => i.title == 'Banca');
      expect(restored.fields.single.value, '4821');
      final out = await vault.exportAttachment(restored.files.single, dir.path);
      expect(out.readAsBytesSync(), src.readAsBytesSync());
      await dir.delete(recursive: true);
    });
    await finish(tester, t);
  });
}
