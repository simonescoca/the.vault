import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_controller.dart';
import 'src/app/platform_services.dart';
import 'src/app/settings.dart';
import 'src/core/crypto/vault_crypto.dart';
import 'src/core/storage/secret_store.dart';
import 'src/ui/app.dart';

/// Set at build time: --dart-define=APP_VERSION=1.0.0
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Geist', 'Geist Mono'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final crypto = await VaultCrypto.init();
  // THEVAULT_DATA lets tests and development run several "devices" on one computer.
  final dataDir = Platform.environment['THEVAULT_DATA'] ?? (await getApplicationSupportDirectory()).path;
  await Directory(dataDir).create(recursive: true);
  final settings = await AppSettings.load(dataDir);
  final secrets = Platform.isLinux ? FileSecretStore('$dataDir/dev-secrets.json') : OsSecretStore();

  await windowManager.ensureInitialized();
  final bounds = settings.windowBounds;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds?.size ?? const Size(1180, 760),
      minimumSize: const Size(960, 620),
      center: bounds == null,
      title: 'The Vault',
      titleBarStyle: Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    ),
    () async {
      if (bounds != null) await windowManager.setBounds(bounds);
      await windowManager.show();
      await windowManager.focus();
    },
  );
  windowManager.addListener(_WindowSaver(settings));

  final app = AppController(
    crypto: crypto,
    secrets: secrets,
    platform: SystemPlatformServices(),
    settings: settings,
    dataDir: dataDir,
    version: appVersion,
  );
  await app.init();
  runApp(TheVaultApp(app: app));
}

/// Remembers the window size and position.
class _WindowSaver with WindowListener {
  _WindowSaver(this.settings);
  final AppSettings settings;
  Timer? _t;

  void _save() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 600), () async {
      settings.windowBounds = await windowManager.getBounds();
      await settings.save();
    });
  }

  @override
  void onWindowResized() => _save();

  @override
  void onWindowMoved() => _save();
}
