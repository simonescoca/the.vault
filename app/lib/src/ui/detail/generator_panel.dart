// Password generator panel (docs/SPEC.md §6.4).
import 'package:flutter/material.dart';

import '../../core/crypto/password_generator.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GeneratorPanel extends StatefulWidget {
  const GeneratorPanel({super.key, required this.onUse, required this.onClose});
  final ValueChanged<String> onUse;
  final VoidCallback onClose;

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  static PasswordOptions _last = const PasswordOptions();
  late PasswordOptions _o = _last;
  late final PasswordGenerator _gen = PasswordGenerator(context.app.crypto.sodium);
  String _value = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_value.isEmpty) _value = _gen.generate(_o);
  }

  void _set(PasswordOptions o) {
    // At least one group stays enabled.
    if (!o.anyEnabled) return;
    setState(() {
      _o = _last = o;
      _value = _gen.generate(o);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    Widget toggle(String label, bool v, PasswordOptions Function(bool) f) => Row(mainAxisSize: MainAxisSize.min, children: [
          VSwitch(value: v, onChanged: (x) => _set(f(x))),
          const SizedBox(width: 7),
          Text(label, style: t.small.copyWith(color: c.text)),
        ]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.inputBorder)),
          child: SelectableText(_value, style: t.value.copyWith(fontSize: 13.5), maxLines: 3),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(l.length, style: t.small),
          Expanded(
            child: Slider(
              value: _o.length.toDouble(),
              min: PasswordOptions.minLength.toDouble(),
              max: PasswordOptions.maxLength.toDouble(),
              divisions: PasswordOptions.maxLength - PasswordOptions.minLength,
              onChanged: (v) => _set(_o.copyWith(length: v.round())),
            ),
          ),
          SizedBox(width: 22, child: Text('${_o.length}', style: t.value, textAlign: TextAlign.right)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 14, runSpacing: 10, children: [
          toggle('A–Z', _o.upper, (v) => _o.copyWith(upper: v)),
          toggle('a–z', _o.lower, (v) => _o.copyWith(lower: v)),
          toggle('0–9', _o.digits, (v) => _o.copyWith(digits: v)),
          toggle(l.symbols, _o.symbols, (v) => _o.copyWith(symbols: v)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          VButton(label: l.regenerate, kind: VButtonKind.secondary, icon: Ic.refreshCw, onPressed: () => setState(() => _value = _gen.generate(_o))),
          const Spacer(),
          VButton(
            label: l.use,
            onPressed: () {
              widget.onUse(_value);
              widget.onClose();
            },
          ),
        ]),
      ],
    );
  }
}
