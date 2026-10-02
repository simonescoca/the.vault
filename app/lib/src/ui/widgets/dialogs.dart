// Small centered dialogs. Confirmations are used only for irreversible actions.
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// A plain panel in the app style (used by all dialogs).
class VPanel extends StatelessWidget {
  const VPanel({super.key, required this.child, this.width = 420, this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 18)});
  final Widget child;
  final double width;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.divider),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 40, offset: const Offset(0, 12))],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The buttons at the bottom of a dialog, aligned right. When the labels are too long for one row
/// (e.g. in another language) they go one under the other instead of overflowing.
class DialogActions extends StatelessWidget {
  const DialogActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: 8,
      overflowSpacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      children: children,
    );
  }
}

Future<T?> showVDialog<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'dialog',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)), child: child),
    ),
  );
}

/// Asks for confirmation. Returns true when the user confirms.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  required String cancelLabel,
  bool danger = true,
}) async {
  final r = await showVDialog<bool>(
    context,
    (ctx) => VPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ctx.text.section.copyWith(fontSize: 15)),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body, style: ctx.text.body.copyWith(color: ctx.colors.text2)),
          ],
          const SizedBox(height: 20),
          DialogActions(
            children: [
              VButton(label: cancelLabel, kind: VButtonKind.secondary, onPressed: () => Navigator.of(ctx).pop(false)),
              VButton(
                label: confirmLabel,
                kind: danger ? VButtonKind.danger : VButtonKind.primary,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return r == true;
}
