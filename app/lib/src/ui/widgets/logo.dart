// The Vault mark: a minimal safe dial (ring, notch, hub).
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

class VaultLogo extends StatelessWidget {
  const VaultLogo({super.key, this.size = 48, this.color, this.filled = false});

  final double size;
  final Color? color;

  /// Dial drawn inside a rounded square (the app icon style).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      size: Size.square(size),
      painter: VaultLogoPainter(
        color: filled ? c.onPrimary : (color ?? c.text),
        background: filled ? c.primary : null,
      ),
    );
  }
}

class VaultLogoPainter extends CustomPainter {
  VaultLogoPainter({required this.color, this.background});
  final Color color;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    if (background != null) {
      final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.225));
      canvas.drawRRect(r, Paint()..color = background!);
    }
    final scale = background != null ? 0.78 : 1.0;
    final ringR = s * 0.36 * scale;
    final stroke = s * 0.07 * scale;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, ringR, paint);
    // Twelve small ticks inside the ring, like a combination dial; the top one is the notch.
    for (var i = 0; i < 12; i++) {
      final a = -pi / 2 + i * pi / 6;
      final outer = ringR - stroke * 1.35;
      final inner = i == 0 ? ringR - stroke * 3.6 : ringR - stroke * 2.0;
      final p = Paint()
        ..color = color.withValues(alpha: i == 0 ? 1 : 0.45)
        ..strokeWidth = i == 0 ? stroke * 0.9 : stroke * 0.42
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center + Offset(cos(a), sin(a)) * outer, center + Offset(cos(a), sin(a)) * inner, p);
    }
    canvas.drawCircle(center, s * 0.075 * scale, Paint()..color = color);
  }

  @override
  bool shouldRepaint(VaultLogoPainter old) => old.color != color || old.background != background;
}
