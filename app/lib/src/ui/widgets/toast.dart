// Short messages at the bottom center ("Copiato", "Spostata nel cestino — Annulla").
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class ToastController extends ChangeNotifier {
  ToastEntry? current;
  Timer? _timer;

  void show(String message, {String? actionLabel, VoidCallback? onAction, Duration duration = const Duration(milliseconds: 2200)}) {
    _timer?.cancel();
    current = ToastEntry(message, actionLabel, onAction, DateTime.now().microsecondsSinceEpoch);
    notifyListeners();
    _timer = Timer(actionLabel != null ? const Duration(seconds: 5) : duration, hide);
  }

  void hide() {
    _timer?.cancel();
    current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ToastEntry {
  ToastEntry(this.message, this.actionLabel, this.onAction, this.id);
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int id;
}

/// Hosts the toasts above [child].
class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.controller, required this.child});
  final ToastController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: IgnorePointer(
            ignoring: false,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final t = controller.current;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                      child: child,
                    ),
                  ),
                  child: t == null
                      ? const SizedBox.shrink()
                      : Center(key: ValueKey(t.id), child: _ToastPill(entry: t, onDone: controller.hide)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.entry, required this.onDone});
  final ToastEntry entry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: EdgeInsets.fromLTRB(16, 9, entry.actionLabel != null ? 8 : 16, 9),
        decoration: BoxDecoration(
          color: c.toastBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(entry.message, style: TextStyle(fontFamily: kSans, fontSize: 13, color: c.toastText, fontWeight: FontWeight.w500)),
            ),
            if (entry.actionLabel != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  entry.onAction?.call();
                  onDone();
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.toastText.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: Text(entry.actionLabel!,
                        style: TextStyle(fontFamily: kSans, fontSize: 13, color: c.toastText, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
