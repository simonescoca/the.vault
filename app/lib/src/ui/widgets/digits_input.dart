// Six-digit inputs: the email code (visible digits in boxes) and the PIN (dots).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class DigitsInput extends StatefulWidget {
  const DigitsInput({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.obscure = false,
    this.enabled = true,
    this.error = false,
    this.controller,
    this.autofocus = true,
  });

  final ValueChanged<String> onCompleted;
  final int length;

  /// PIN style: dots instead of digits.
  final bool obscure;
  final bool enabled;
  final bool error;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  State<DigitsInput> createState() => DigitsInputState();
}

class DigitsInputState extends State<DigitsInput> with SingleTickerProviderStateMixin {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    // Take the keyboard right away, also when the previous screen still holds it (e.g. after locking).
    if (widget.autofocus) _focusSoon();
  }

  @override
  void didUpdateWidget(DigitsInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Back from "checking…" or from a wait: the keyboard goes back to the digits.
    if (widget.enabled && !oldWidget.enabled && widget.autofocus) _focusSoon();
  }

  /// Focuses after the next frame: a disabled field cannot take the focus until it is rebuilt enabled.
  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _focus.requestFocus();
    });
  }

  String? _reported;

  void _changed() {
    setState(() {});
    final v = _c.text;
    if (v.length == widget.length && v != _reported) {
      _reported = v;
      // Report after the frame: the listener may clear or reject the input.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted(v);
      });
    } else if (v.length < widget.length) {
      _reported = null;
    }
  }

  /// Clears the digits with a small shake (wrong code / PIN).
  void reject() {
    _shake.forward(from: 0);
    _c.clear();
    _focusSoon();
  }

  void clear() => _c.clear();

  @override
  void dispose() {
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _c.text;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : 8 * (1 - t) * (t * 22).remainder(2) * ((t * 22).floor().isEven ? 1 : -1);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The real (invisible) field receives typing and paste.
            Opacity(
              opacity: 0,
              child: SizedBox(
                width: 10,
                child: TextField(
                  controller: _c,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DigitsFormatter(widget.length)],
                  showCursor: false,
                  enableInteractiveSelection: false,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) SizedBox(width: (!widget.obscure && i == widget.length ~/ 2) ? 18 : 8),
                  _box(context, i, text, c),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(BuildContext context, int i, String text, VaultColors c) {
    final filled = i < text.length;
    final active = _focus.hasFocus && i == text.length.clamp(0, widget.length - 1) && widget.enabled;
    if (widget.obscure) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 14,
        height: 14,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? (widget.error ? c.danger : c.primary) : Colors.transparent,
          border: Border.all(color: widget.error ? c.danger : (active ? c.primary : c.text3), width: 1.4),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 44,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: widget.error ? c.danger : (active ? c.primary : c.inputBorder), width: active ? 1.4 : 1),
      ),
      child: Text(filled ? text[i] : '', style: TextStyle(fontFamily: kMono, fontSize: 24, fontWeight: FontWeight.w500, color: c.text)),
    );
  }
}

class _DigitsFormatter extends TextInputFormatter {
  _DigitsFormatter(this.max);
  final int max;
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > max) digits = digits.substring(0, max);
    return TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
  }
}
