// UI tests use the app's real fonts, so text takes the same space as in the real app.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (family, weights) in [('Geist', [400, 500, 600, 700]), ('GeistMono', [400, 500])]) {
    final loader = FontLoader(family);
    for (final w in weights) {
      loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
    }
    await loader.load();
  }
  await testMain();
}
