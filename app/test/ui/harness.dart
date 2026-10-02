// Builds the real app (offline, no server) for widget tests.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/app/app_controller.dart';
import 'package:the_vault/src/app/platform_services.dart';
import 'package:the_vault/src/app/settings.dart';
import 'package:the_vault/src/core/account/identity.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';
import 'package:the_vault/src/ui/app.dart';
import 'package:the_vault/src/ui/detail/detail_view.dart';

class FakePlatform implements PlatformServices {
  String? clipboard;
  final opened = <Uri>[];
  final openedFiles = <String>[];
  bool biometrics = false;

  @override
  String get platform => 'macos';
  @override
  String get biometricName => 'Touch ID';
  @override
  String defaultDeviceName() => 'Test Mac';
  @override
  Future<bool> biometricsAvailable() async => biometrics;
  @override
  Future<bool> authenticate(String reason) async => biometrics;
  @override
  Future<void> openUrl(Uri uri) async => opened.add(uri);
  @override
  Future<bool> openFile(String path) async {
    openedFiles.add(path);
    return true;
  }

  @override
  Future<List<File>> pickFiles() async => const [];
  @override
  Future<String?> pickFile({List<String>? extensions}) async => null;
  @override
  Future<String?> saveFileDialog(String suggestedName, {List<String>? extensions}) async => null;
  @override
  Future<void> setClipboard(String text) async => clipboard = text;
  @override
  Future<String?> getClipboard() async => clipboard;
}

class TestApp {
  TestApp(this.app, this.platform, this.dir);
  final AppController app;
  final FakePlatform platform;
  final Directory dir;

  VaultController get vault => app.session!.vault;
}

/// An unlocked vault (Italian UI) with the given entries.
Future<TestApp> pumpUnlockedApp(WidgetTester tester, {List<Item> items = const [], String language = 'it'}) async {
  late TestApp t;
  await tester.runAsync(() async {
    final crypto = await VaultCrypto.init();
    final dir = await Directory.systemTemp.createTemp('tv-ui');
    final secrets = MemorySecretStore();
    final kp = crypto.newBoxKeyPair();
    await secrets.writeIdentity(Identity(
      server: Uri.parse('http://127.0.0.1:9'),
      email: 'me@example.com',
      userId: 'u1',
      deviceId: 'd1',
      deviceName: 'Test Mac',
      platform: 'macos',
      token: 'tok',
      devicePublicKey: kp.publicKey,
      deviceSecretKey: kp.secretKey.extractBytes(),
      status: 'active',
    ));
    await secrets.writeVaultKey(crypto.newVaultKey().extractBytes());
    final settings = AppSettings(File('${dir.path}/settings.json'))
      ..language = language
      ..clipboardSeconds = 0;
    final platform = FakePlatform();
    final app = AppController(crypto: crypto, secrets: secrets, platform: platform, settings: settings, dataDir: dir.path, online: false);
    await app.lock.setPin('123456');
    await app.init();
    await app.unlockWithPin('123456');
    for (final i in items) {
      app.session!.vault.save(i);
    }
    t = TestApp(app, platform, dir);
  });
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TheVaultApp(app: t.app));
  await tester.pumpAndSettle();
  return t;
}

/// Lets real asynchronous work (e.g. PIN hashing in a background isolate) finish, up to [timeout].
Future<void> waitUntil(WidgetTester tester, bool Function() done, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('condition not reached within $timeout');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Ends a test cleanly (no timers left).
Future<void> finish(WidgetTester tester, TestApp t) async {
  t.app.lockNow();
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Finder fieldWithHint(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint, description: 'TextField(hint: $hint)');

/// Presses a shortcut with the command key of the system running the tests (⌘ on macOS, Ctrl elsewhere).
Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final mod = Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(mod);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

/// Restricts a finder to the entry shown on the right.
Finder inDetail(Finder f) => find.descendant(of: find.byType(DetailView), matching: f);

Item sampleItem(String title, List<(String, String)> rows, {bool favorite = false}) {
  var n = 0;
  return Item(
    id: VaultController.newId(),
    title: title,
    fields: [for (final r in rows) Field(id: 'r${n++}', key: r.$1, value: r.$2)],
    favorite: favorite,
    created: DateTime(2026, 1, 1),
    updated: DateTime(2026, 1, 1),
  );
}
