// Basic building blocks: buttons, icon buttons, text fields, hover helper.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Rebuilds with the hover state of the pointer.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.cursor = MouseCursor.defer});
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: widget.builder(context, _h),
      );
}

enum VButtonKind { primary, secondary, text, danger }

class VButton extends StatelessWidget {
  const VButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = VButtonKind.primary,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final VButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (kind) {
      VButtonKind.primary => (c.primary, c.onPrimary, Colors.transparent),
      VButtonKind.secondary => (Colors.transparent, c.text, c.inputBorder),
      VButtonKind.text => (Colors.transparent, c.text2, Colors.transparent),
      VButtonKind.danger => (c.danger, Colors.white, Colors.transparent),
    };
    final h = large ? 40.0 : 32.0;
    return Hover(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) {
        final hoverBg = switch (kind) {
          VButtonKind.primary || VButtonKind.danger => bg.withValues(alpha: hovered && enabled ? 0.86 : 1),
          _ => hovered && enabled ? c.hover : bg,
        };
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg))
            else if (icon != null)
              Icon(icon, size: 15, color: fg),
            if (busy || icon != null) const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: kSans, fontSize: large ? 14 : 13, fontWeight: FontWeight.w500, color: fg),
              ),
            ),
          ],
        );
        return Opacity(
          opacity: enabled || busy ? 1 : 0.4,
          child: GestureDetector(
            onTap: enabled ? onPressed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: h,
              padding: EdgeInsets.symmetric(horizontal: kind == VButtonKind.text ? 8 : (large ? 18 : 13)),
              decoration: BoxDecoration(
                color: hoverBg,
                borderRadius: BorderRadius.circular(large ? 9 : 7),
                border: Border.all(color: border),
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class VIconButton extends StatelessWidget {
  const VIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 16,
    this.color,
    this.box = 28,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final double box;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = Hover(
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: box,
          height: box,
          decoration: BoxDecoration(
            color: (hovered && onPressed != null) || active ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: size, color: onPressed == null ? c.text3.withValues(alpha: 0.5) : (color ?? (hovered ? c.text : c.text2))),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Gives the keyboard focus to the first field inside [child] as soon as it appears.
/// (`autofocus` alone does nothing while the previous screen, still fading out, holds the focus.)
class TakeFocus extends StatefulWidget {
  const TakeFocus({super.key, required this.child});
  final Widget child;

  @override
  State<TakeFocus> createState() => _TakeFocusState();
}

class _TakeFocusState extends State<TakeFocus> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final n in _node.descendants) {
        if (n.canRequestFocus && !n.skipTraversal) return n.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}

/// Text field in the style of the app.
class VTextField extends StatelessWidget {
  const VTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.mono = false,
    this.autofocus = false,
    this.obscure = false,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.style,
    this.maxLines = 1,
    this.minLines,
    this.error,
    this.enabled = true,
    this.borderless = false,
    this.prefix,
    this.suffix,
    this.textInputAction,
    this.dense = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final bool mono;
  final bool autofocus;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;
  final String? error;
  final bool enabled;
  final bool borderless;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final base = style ?? (mono ? t.value : t.body);
    OutlineInputBorder border(Color color, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: color, width: w));
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      style: base,
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      enabled: enabled,
      textInputAction: textInputAction,
      cursorWidth: 1.4,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: base.copyWith(color: c.text3),
        filled: !borderless,
        fillColor: c.inputBg,
        prefixIcon: prefix,
        suffixIcon: suffix,
        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 20),
        suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 20),
        contentPadding: borderless
            ? const EdgeInsets.symmetric(vertical: 6)
            : EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 7 : 10),
        border: borderless ? InputBorder.none : border(c.inputBorder),
        enabledBorder: borderless ? InputBorder.none : border(c.inputBorder),
        disabledBorder: borderless ? InputBorder.none : border(c.divider),
        focusedBorder: borderless ? InputBorder.none : border(c.primary.withValues(alpha: 0.7), 1.2),
        errorText: error,
        errorStyle: t.small.copyWith(color: c.danger),
        errorMaxLines: 3,
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 1.2),
      ),
    );
    return autofocus ? TakeFocus(child: field) : field;
  }
}

/// A thin horizontal or vertical line.
class VDivider extends StatelessWidget {
  const VDivider({super.key, this.vertical = false});
  final bool vertical;
  @override
  Widget build(BuildContext context) => vertical
      ? Container(width: 1, color: context.colors.divider)
      : Container(height: 1, color: context.colors.divider);
}

/// Segmented choice (theme, language, timers).
class VSegmented<T> extends StatelessWidget {
  const VSegmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.inputBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            Hover(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: v == value ? c.bg : (hovered ? c.hover : Colors.transparent),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: v == value ? [BoxShadow(color: c.shadow, blurRadius: 3, offset: const Offset(0, 1))] : null,
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontFamily: kSans, fontSize: 12.5, fontWeight: v == value ? FontWeight.w600 : FontWeight.w500, color: v == value ? c.text : c.text2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small switch in the monochrome style.
class VSwitch extends StatelessWidget {
  const VSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: MouseRegion(
        cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? c.primary : c.selected,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 16, height: 16, decoration: BoxDecoration(color: value ? c.onPrimary : c.bg, shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }
}
