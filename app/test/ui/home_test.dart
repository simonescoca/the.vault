import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';
import 'package:the_vault/src/ui/detail/detail_view.dart';
import 'package:the_vault/src/ui/icons.dart';

import 'harness.dart';

void main() {
  testWidgets('new entry: suggested keys, empty rows dropped, title from the site', (tester) async {
    final t = await pumpUnlockedApp(tester);
    expect(find.text('Ancora nessuna password.\nCreane una con +'), findsOneWidget);

    await tester.tap(find.byIcon(Ic.plus).first);
    await tester.pumpAndSettle();
    // Three rows with the suggestions as grey hints.
    expect(fieldWithHint('sito web'), findsOneWidget);
    expect(fieldWithHint('email'), findsOneWidget);
    expect(fieldWithHint('password'), findsOneWidget);
    expect(fieldWithHint('Descrizione'), findsOneWidget);

    final values = fieldWithHint('valore');
    expect(values, findsNWidgets(3));
    await tester.enterText(values.at(0), 'www.netflix.com');
    await tester.enterText(values.at(2), 'S3gret0!');
    await tester.pump();
    // The title hint becomes the site name.
    expect(fieldWithHint('Netflix'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final items = t.vault.list(Section.all);
    expect(items, hasLength(1));
    final it = items.single;
    expect(it.title, 'Netflix');
    expect(it.fields.map((f) => '${f.key}=${f.value}'), ['sito web=www.netflix.com', 'password=S3gret0!']);
    // View mode shows the entry; the empty description is not shown.
    expect(find.text('Netflix'), findsWidgets);
    expect(fieldWithHint('Descrizione'), findsNothing);
    await finish(tester, t);
  });

  testWidgets('a title is required when there is no website', (tester) async {
    final t = await pumpUnlockedApp(tester);
    await tester.tap(find.byIcon(Ic.plus).first);
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint('valore').at(1), 'me@example.com');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Dai un titolo a questa voce'), findsOneWidget);
    expect(t.vault.list(Section.all), isEmpty);
    await tester.enterText(fieldWithHint('Titolo'), 'Posta');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(t.vault.list(Section.all).single.fields.single.key, 'email');
    await finish(tester, t);
  });

  testWidgets('rows: at least one stays, added rows keep an empty key', (tester) async {
    final t = await pumpUnlockedApp(tester);
    await tester.tap(find.byIcon(Ic.plus).first);
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint('Titolo'), 'Note');
    // Remove two rows: the third remove button is disabled.
    await tester.tap(find.byIcon(Ic.minus).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Ic.minus).first);
    await tester.pumpAndSettle();
    expect(fieldWithHint('valore'), findsOneWidget);
    await tester.tap(find.byIcon(Ic.minus).first);
    await tester.pumpAndSettle();
    expect(fieldWithHint('valore'), findsOneWidget, reason: 'the last row cannot be removed');
    // Add a row: generic hint "chiave", left empty → saved without key.
    await tester.tap(find.text('Aggiungi riga'));
    await tester.pumpAndSettle();
    expect(fieldWithHint('chiave'), findsOneWidget);
    await tester.enterText(fieldWithHint('valore').last, 'testo libero');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    final it = t.vault.list(Section.all).single;
    expect(it.fields.map((f) => [f.key, f.value]), [
      ['', 'testo libero'],
    ]);
    await finish(tester, t);
  });

  testWidgets('view: click copies, eye hides and the choice is saved, links open the browser', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [
      sampleItem('Banca', [('sito web', 'bank.example.com'), ('email', 'me@example.com'), ('pin', '4821')]),
    ]);
    await tester.tap(find.text('Banca').first);
    await tester.pumpAndSettle();

    await tester.tap(inDetail(find.text('4821')));
    await tester.pump();
    expect(t.platform.clipboard, '4821');
    expect(find.text('Copiato'), findsWidgets);

    // Emails are not links: clicking copies.
    await tester.tap(inDetail(find.text('me@example.com')));
    await tester.pump();
    expect(t.platform.clipboard, 'me@example.com');
    expect(t.platform.opened, isEmpty);

    // Websites open in the browser.
    await tester.tap(inDetail(find.text('bank.example.com')));
    await tester.pump();
    expect(t.platform.opened.single.toString(), 'https://bank.example.com');

    // Eye: hide the PIN; the choice is saved in the entry.
    await tester.pump(const Duration(milliseconds: 1500)); // the "Copiato" labels go away
    final pinRow = find.ancestor(of: inDetail(find.text('4821')), matching: find.byType(FieldRow));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(pinRow));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: pinRow, matching: find.byIcon(Ic.eye)));
    await tester.pumpAndSettle();
    expect(inDetail(find.text('4821')), findsNothing);
    expect(inDetail(find.text('•' * 12)), findsOneWidget);
    expect(t.vault.list(Section.all).single.fields.last.hidden, isTrue);
    // A hidden value is still copied with a click, without showing it.
    await tester.tap(inDetail(find.text('•' * 12)));
    await tester.pump();
    expect(t.platform.clipboard, '4821');
    await gesture.removePointer();
    await finish(tester, t);
  });

  testWidgets('trash: move with undo, restore, delete permanently with confirmation', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Amazon', [('email', 'a@b.it')]), sampleItem('Zeta', [('x', 'y')])]);
    await tester.tap(find.text('Amazon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Ic.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sposta nel cestino'));
    await tester.pumpAndSettle();
    expect(find.text('Spostata nel cestino'), findsOneWidget);
    expect(t.vault.list(Section.all).map((i) => i.title), ['Zeta']);
    // Undo from the message.
    await tester.tap(find.text('Annulla').last);
    await tester.pumpAndSettle();
    expect(t.vault.list(Section.all).map((i) => i.title), ['Amazon', 'Zeta']);

    // Trash again with the keyboard shortcut, then open the trash.
    await tester.tap(find.text('Amazon').first);
    await tester.pumpAndSettle();
    if (Platform.isMacOS) {
      await shortcut(tester, LogicalKeyboardKey.backspace); // ⌘⌫
    } else {
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // Canc
      await tester.pumpAndSettle();
    }
    expect(t.vault.list(Section.trash).map((i) => i.title), ['Amazon']);
    await tester.tap(find.text('Cestino'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amazon').first);
    await tester.pumpAndSettle();
    expect(find.text('Questa voce è nel cestino'), findsOneWidget);
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Non si potrà recuperare'), findsOneWidget);
    await tester.tap(find.text('Elimina definitivamente').last);
    await tester.pumpAndSettle();
    expect(t.vault.list(Section.trash), isEmpty);
    expect(t.vault.list(Section.all).map((i) => i.title), ['Zeta']);
    await finish(tester, t);
  });

  testWidgets('search filters by title, key and visible value, ignoring accents', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [
      sampleItem('Università', [('matricola', '123')]),
      sampleItem('Amazon', [('email', 'shop@example.com')]),
      sampleItem('Banca', [('pin', '999')]),
    ]);
    await tester.enterText(fieldWithHint('Cerca'), 'universita');
    await tester.pumpAndSettle();
    expect(find.text('Università'), findsWidgets);
    expect(find.text('Amazon'), findsNothing);
    await tester.enterText(fieldWithHint('Cerca'), 'shop@');
    await tester.pumpAndSettle();
    expect(find.text('Amazon'), findsWidgets);
    expect(find.text('Banca'), findsNothing);
    await tester.enterText(fieldWithHint('Cerca'), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nessun risultato per «zzz»'), findsOneWidget);
    await finish(tester, t);
  });

  testWidgets('favorites section and star', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Netflix', [('a', 'b')]), sampleItem('Spotify', [('c', 'd')])]);
    await tester.tap(find.text('Spotify').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aggiungi ai preferiti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferiti'));
    await tester.pumpAndSettle();
    expect(t.vault.list(Section.favorites).map((i) => i.title), ['Spotify']);
    expect(find.text('Netflix'), findsNothing);
    await finish(tester, t);
  });

  testWidgets('keyboard: Tab goes title → key → value → next row, Enter adds a row', (tester) async {
    final t = await pumpUnlockedApp(tester);
    await tester.tap(find.byIcon(Ic.plus).first);
    await tester.pumpAndSettle();
    bool focused(Finder f) =>
        tester.widget<EditableText>(find.descendant(of: f, matching: find.byType(EditableText))).focusNode.hasPrimaryFocus;
    expect(focused(fieldWithHint('Titolo')), isTrue, reason: 'a new entry starts from the title');
    tester.testTextInput.enterText('Banca');
    final values = fieldWithHint('valore');
    final order = [fieldWithHint('sito web'), values.at(0), fieldWithHint('email'), values.at(1), fieldWithHint('password'), values.at(2)];
    for (final f in order) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(f), isTrue, reason: 'Tab should reach $f');
    }
    // What is typed lands in the focused field; Enter in the last value adds a new row and moves there.
    tester.testTextInput.enterText('1234');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fieldWithHint('chiave'), findsOneWidget);
    expect(focused(fieldWithHint('chiave')), isTrue);
    tester.testTextInput.enterText('pin');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    tester.testTextInput.enterText('0000');
    await tester.pump();
    // Shift+Tab goes back.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(focused(fieldWithHint('chiave')), isTrue);
    // ⌘S / Ctrl+S saves.
    await shortcut(tester, LogicalKeyboardKey.keyS);
    final it = t.vault.list(Section.all).single;
    expect(it.title, 'Banca');
    expect(it.fields.map((f) => '${f.key}=${f.value}'), ['password=1234', 'pin=0000']);
    await finish(tester, t);
  });
}
