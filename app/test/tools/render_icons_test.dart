// Draws the app icons (macOS app icon set, Windows .ico sizes).
// Run on purpose only: THEVAULT_RENDER_ICONS=1 flutter test test/tools/render_icons_test.dart
// then build the .ico with:  scripts/make-icons.sh
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Graphite tile with a light safe dial, the same mark as the app logo.
class AppIconPainter {
  AppIconPainter({required this.mac});

  /// macOS icons leave a margin around the tile and cast a shadow (Big Sur style);
  /// Windows icons use almost the whole canvas.
  final bool mac;

  void paint(Canvas canvas, double size) {
    final margin = mac ? size * 100 / 1024 : size * (size <= 32 ? 0.0 : 0.04);
    final tile = Rect.fromLTWH(margin, margin, size - 2 * margin, size - 2 * margin);
    final radius = tile.width * (mac ? 0.225 : 0.2);
    final rrect = RRect.fromRectAndRadius(tile, Radius.circular(radius));

    if (mac) {
      canvas.drawRRect(
        rrect.shift(Offset(0, size * 10 / 1024)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 14 / 1024),
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(tile.topCenter, tile.bottomCenter, const [Color(0xFF34343A), Color(0xFF141416)]),
    );
    // A thin light edge on top, like a machined metal plate.
    if (size >= 64) {
      canvas.drawRRect(
        rrect.deflate(size * 1.5 / 1024),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, size * 3 / 1024)
          ..shader = ui.Gradient.linear(
            tile.topCenter,
            tile.bottomCenter,
            [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.02)],
          ),
      );
    }

    final center = tile.center;
    final s = tile.width;
    final small = size <= 32;
    final ringR = s * (small ? 0.31 : 0.30);
    final stroke = s * (small ? 0.085 : 0.055);
    const light = Color(0xFFF2F2F0);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..color = light
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // Tiny sizes keep only the notch: twelve ticks would turn into grey noise.
    for (var i = 0; i < (small ? 1 : 12); i++) {
      final a = -pi / 2 + i * pi / 6;
      final outer = ringR - stroke * (small ? 1.2 : 1.4);
      final inner = i == 0 ? ringR - stroke * (small ? 2.6 : 3.6) : ringR - stroke * 2.1;
      canvas.drawLine(
        center + Offset(cos(a), sin(a)) * outer,
        center + Offset(cos(a), sin(a)) * inner,
        Paint()
          ..color = light.withValues(alpha: i == 0 ? 1 : 0.42)
          ..strokeWidth = i == 0 ? stroke * 0.9 : stroke * 0.42
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(center, s * (small ? 0.085 : 0.062), Paint()..color = light);
  }
}

Future<void> _render(AppIconPainter painter, int size, String path) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  final enabled = Platform.environment['THEVAULT_RENDER_ICONS'] == '1';

  testWidgets('render app icons', (tester) async {
    await tester.runAsync(() async {
      const macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
        await _render(AppIconPainter(mac: true), size, '$macDir/app_icon_$size.png');
      }
      for (final size in [16, 20, 24, 32, 40, 48, 64, 256]) {
        await _render(AppIconPainter(mac: false), size, 'build/icons/windows/$size.png');
      }
      await _render(AppIconPainter(mac: false), 256, 'assets/icon/app_icon.png');
    });
  }, skip: !enabled);
}
