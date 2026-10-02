// Preferences of this computer (not secret): theme, language, timers, window position.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File _file;

  ThemeMode themeMode = ThemeMode.system;

  /// 'system' | 'it' | 'en'
  String language = 'system';
  int autoLockMinutes = 5;

  /// 0 = never
  int clipboardSeconds = 60;
  Rect? windowBounds;

  static const autoLockChoices = [1, 5, 15, 30, 60];
  static const clipboardChoices = [30, 60, 120, 300, 0];

  static Future<AppSettings> load(String dir) async {
    final s = AppSettings(File('$dir/settings.json'));
    try {
      final j = jsonDecode(await s._file.readAsString()) as Map<String, dynamic>;
      s.themeMode = ThemeMode.values.firstWhere((m) => m.name == j['theme'], orElse: () => ThemeMode.system);
      s.language = (j['language'] as String?) ?? 'system';
      s.autoLockMinutes = (j['autoLock'] as num?)?.toInt() ?? 5;
      s.clipboardSeconds = (j['clipboard'] as num?)?.toInt() ?? 60;
      final w = j['window'] as List?;
      if (w != null && w.length == 4) {
        s.windowBounds = Rect.fromLTWH((w[0] as num).toDouble(), (w[1] as num).toDouble(), (w[2] as num).toDouble(), (w[3] as num).toDouble());
      }
    } catch (_) {}
    return s;
  }

  Future<void> save() async {
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'theme': themeMode.name,
        'language': language,
        'autoLock': autoLockMinutes,
        'clipboard': clipboardSeconds,
        if (windowBounds != null) 'window': [windowBounds!.left, windowBounds!.top, windowBounds!.width, windowBounds!.height],
      }));
    } catch (_) {}
  }

  /// The language actually used: Italian if chosen or if the system is Italian, otherwise English.
  Locale effectiveLocale(Locale system) {
    if (language == 'it') return const Locale('it');
    if (language == 'en') return const Locale('en');
    return systemLocale([system]);
  }

  /// The chosen language, or null to follow the system (see [systemLocale]).
  Locale? get chosenLocale => language == 'it' || language == 'en' ? Locale(language) : null;

  /// The language that follows the system: Italian on an Italian system, English otherwise.
  static Locale systemLocale(List<Locale>? preferred) =>
      preferred != null && preferred.isNotEmpty && preferred.first.languageCode == 'it' ? const Locale('it') : const Locale('en');
}
