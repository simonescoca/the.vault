import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/app/app_controller.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';
import 'package:the_vault/src/ui/home/home_screen.dart';
import 'package:the_vault/src/ui/icons.dart';

import 'harness.dart';

void main() {
  testWidgets('lock: wrong PIN is refused, the right one opens the vault', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Banca', [('pin', '4821')])]);
    await shortcut(tester, LogicalKeyboardKey.keyL);
    expect(t.app.phase, AppPhase.locked);
    expect(find.text('The Vault è bloccato'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('Banca'), findsNothing, reason: 'nothing of the vault is visible while locked');

    tester.testTextInput.enterText('000000');
    await tester.pump();
    await waitUntil(tester, () => find.textContaining('PIN errato').evaluate().isNotEmpty);
    expect(t.app.phase, AppPhase.locked);

    tester.testTextInput.enterText('123456');
    await tester.pump();
    await waitUntil(tester, () => t.app.phase == AppPhase.unlocked);
    expect(find.text('Banca'), findsWidgets);
    await finish(tester, t);
  });

  testWidgets('text with a link opens the link; a plain email is never a link', (tester) async {
    final item = sampleItem('Banca', [('accesso', 'Area clienti'), ('email', 'me@example.com'), ('supporto', 'help@bank.example.com')]);
    final withLinks = item.copyWith(fields: [
      item.fields[0].copyWith(link: 'https://bank.example.com/login'),
      item.fields[1],
      // A link the user attached on purpose is respected, even on an email.
      item.fields[2].copyWith(link: 'https://bank.example.com/help'),
    ]);
    final t = await pumpUnlockedApp(tester, items: [withLinks]);
    await tester.tap(find.text('Banca').first);
    await tester.pumpAndSettle();

    final link = inDetail(find.text('Area clienti'));
    expect(tester.widget<Text>(link).style?.decoration, TextDecoration.underline);
    await tester.tap(link);
    await tester.pump();
    expect(t.platform.opened.map((u) => '$u'), ['https://bank.example.com/login']);

    final email = inDetail(find.text('me@example.com'));
    expect(tester.widget<Text>(email).style?.decoration, isNot(TextDecoration.underline));
    await tester.tap(email);
    await tester.pump();
    expect(t.platform.opened, hasLength(1), reason: 'emails are not links');
    expect(t.platform.clipboard, 'me@example.com');

    await tester.tap(inDetail(find.text('help@bank.example.com')));
    await tester.pump();
    expect(t.platform.opened.map((u) => '$u'), ['https://bank.example.com/login', 'https://bank.example.com/help']);
    await finish(tester, t);
  });

  testWidgets('description and attachments: hidden when empty, always there while editing', (tester) async {
    final t = await pumpUnlockedApp(tester, items: [sampleItem('Wi-Fi', [('rete', 'Casa')])]);
    await tester.tap(find.text('Wi-Fi').first);
    await tester.pumpAndSettle();
    expect(inDetail(find.text('Allegati')), findsNothing);
    expect(fieldWithHint('Descrizione'), findsNothing);

    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    expect(find.text('Allegati'), findsOneWidget);
    expect(fieldWithHint('Descrizione'), findsOneWidget);
    await tester.enterText(fieldWithHint('Descrizione'), 'Router in salotto');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(inDetail(find.text('Router in salotto')), findsOneWidget);
    expect(inDetail(find.text('Allegati')), findsNothing);
    expect(t.vault.list(Section.all).single.description, 'Router in salotto');
    await finish(tester, t);
  });

  testWidgets('English, and light/dark following the system', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final t = await pumpUnlockedApp(tester, language: 'en');
    expect(fieldWithHint('Search'), findsOneWidget);
    Brightness brightness() => Theme.of(tester.element(find.byType(HomeScreen))).brightness;
    expect(brightness(), Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);

    await tester.tap(find.byIcon(Ic.plus).first);
    await tester.pumpAndSettle();
    expect(fieldWithHint('sito web'), findsNothing);
    expect(fieldWithHint('website'), findsOneWidget);
    expect(fieldWithHint('Description'), findsOneWidget);
    await finish(tester, t);
  });

  testWidgets('"system" language: Italian on an Italian computer, English otherwise', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('it', 'IT');
    tester.platformDispatcher.localesTestValue = const [Locale('it', 'IT')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final t = await pumpUnlockedApp(tester, language: 'system');
    expect(fieldWithHint('Cerca'), findsOneWidget);
    tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    await tester.pumpAndSettle();
    expect(fieldWithHint('Search'), findsOneWidget);
    await finish(tester, t);
  });
}
