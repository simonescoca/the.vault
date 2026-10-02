import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

import 'harness.dart';

void main() {
  testWidgets('attachments: choose a file, save, open the decrypted copy, save a copy, hidden when none', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Contratti', [('numero', '42')])]);
    late Directory dir;
    late File src;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('tv-att');
      src = File('${dir.path}/contratto.pdf')..writeAsBytesSync(List.generate(70000, (i) => i % 251));
    });
    t.platform.filesToPick = [src];

    await tester.tap(find.text('Contratti').first);
    await tester.pumpAndSettle();
    expect(inDetail(find.text('Allegati')), findsNothing, reason: 'no attachments: the section is hidden');
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('scegli…'));
    await tester.tap(find.text('scegli…'));
    // The file is encrypted in the background.
    await waitUntil(tester, () => find.text('contratto.pdf').evaluate().isNotEmpty);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final item = t.vault.list(Section.all).single;
    expect(item.files.single.name, 'contratto.pdf');
    expect(item.files.single.size, 70000);
    expect(inDetail(find.text('Allegati')), findsOneWidget);

    // Click: decrypted into the app's temporary folder and opened with the default app.
    await tester.tap(inDetail(find.text('contratto.pdf')));
    await waitUntil(tester, () => t.platform.openedFiles.isNotEmpty);
    final opened = File(t.platform.openedFiles.single);
    await tester.runAsync(() async {
      expect(await opened.readAsBytes(), await src.readAsBytes());
      expect(opened.path, startsWith(t.app.openDir));
    });

    // Right click → "Salva una copia…" writes the decrypted file where the user chooses.
    t.platform.saveTo = '${dir.path}/copia.pdf';
    final gesture = await tester.startGesture(tester.getCenter(inDetail(find.text('contratto.pdf'))), buttons: kSecondaryButton);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva una copia…'));
    await waitUntil(tester, () => find.text('File salvato').evaluate().isNotEmpty);
    await tester.runAsync(() async {
      expect(await File('${dir.path}/copia.pdf').readAsBytes(), await src.readAsBytes());
      await dir.delete(recursive: true);
    });

    // Locking removes the decrypted copies.
    expect(Directory(t.app.openDir).existsSync(), isTrue);
    t.app.lockNow();
    await waitUntil(tester, () => !Directory(t.app.openDir).existsSync());
    await finish(tester, t);
  });
}
