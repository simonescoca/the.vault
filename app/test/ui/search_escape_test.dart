import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_vault/src/core/vault/vault_controller.dart';

import 'harness.dart';

void main() {
  testWidgets('Esc clears the search also after choosing a result', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Netflix', [('a', 'b')]), sampleItem('Spotify', [('c', 'd')])]);
    await shortcut(tester, LogicalKeyboardKey.keyF);
    tester.testTextInput.enterText('netf');
    await tester.pumpAndSettle();
    expect(find.text('Spotify'), findsNothing);
    await tester.tap(find.text('Netflix').first, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Spotify'), findsOneWidget, reason: 'the search is cleared');
    expect(find.text('Netflix'), findsWidgets, reason: 'and the chosen entry stays selected');
    await finish(tester, t);
  });

  testWidgets('shortcuts keep working after saving an edit or clicking outside a field', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Netflix', [('a', 'b')])]);
    await tester.tap(find.text('Netflix').first, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await shortcut(tester, LogicalKeyboardKey.keyE);
    await tester.tap(fieldWithHint('Descrizione'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('nota');
    await shortcut(tester, LogicalKeyboardKey.keyS); // the focused field disappears with the editor
    expect(t.vault.list(Section.all).single.description, 'nota');
    await shortcut(tester, LogicalKeyboardKey.keyN);
    expect(fieldWithHint('sito web'), findsOneWidget, reason: '⌘N/Ctrl+N works right after saving');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Vuoi scartare le modifiche?'), findsNothing, reason: 'nothing was typed: no question');
    expect(fieldWithHint('sito web'), findsNothing);

    // Opening the editor and clicking in a field without typing is not a change either.
    await shortcut(tester, LogicalKeyboardKey.keyE);
    await tester.tap(fieldWithHint('Descrizione'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Vuoi scartare le modifiche?'), findsNothing);
    expect(find.text('Modifica'), findsOneWidget, reason: 'back to viewing');
    await finish(tester, t);
  });
}
