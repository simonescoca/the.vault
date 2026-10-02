// Choosing the app PIN, then (if available) Touch ID / Windows Hello.
import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/digits_input.dart';
import '../widgets/logo.dart';

/// Shown when the vault key is on this device but no PIN was chosen yet (interrupted first access).
class PinSetupScreen extends StatelessWidget {
  const PinSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => PinAndBiometrics(onDone: (pin) => context.app.pinChosen(pin));
}

/// Two steps: PIN (twice), then the biometric offer. [onDone] receives the PIN.
class PinAndBiometrics extends StatefulWidget {
  const PinAndBiometrics({super.key, required this.onDone});
  final Future<void> Function(String pin) onDone;

  @override
  State<PinAndBiometrics> createState() => _PinAndBiometricsState();
}

class _PinAndBiometricsState extends State<PinAndBiometrics> {
  String? _first;
  String? _pin;
  bool _mismatch = false;
  bool _askBiometrics = false;
  bool _busy = false;
  final _inputKey = GlobalKey<DigitsInputState>();

  Future<void> _entered(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _mismatch = false;
      });
      _inputKey.currentState?.clear();
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _mismatch = true;
      });
      _inputKey.currentState?.reject();
      return;
    }
    _pin = pin;
    final app = context.app;
    if (await app.platform.biometricsAvailable()) {
      setState(() => _askBiometrics = true);
    } else {
      await _finish();
    }
  }

  Future<void> _finish({bool biometrics = false}) async {
    setState(() => _busy = true);
    final app = context.app;
    if (biometrics) {
      final ok = await app.platform.authenticate(context.l.biometricReason);
      await app.lock.setBiometricsEnabled(ok);
    }
    await widget.onDone(_pin!);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    if (_askBiometrics) {
      final method = context.app.platform.biometricName;
      return CenteredPage(children: [
        Center(child: Icon(method == 'Touch ID' ? Icons.fingerprint : Icons.face_retouching_natural, size: 44, color: context.colors.text)),
        const SizedBox(height: 24),
        Text(l.biometricsTitle(method), style: t.headline, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(l.biometricsSubtitle, style: t.subhead, textAlign: TextAlign.center),
        const SizedBox(height: 32),
        VButton(label: l.enable, large: true, expand: true, busy: _busy, onPressed: () => _finish(biometrics: true)),
        const SizedBox(height: 8),
        VButton(label: l.notNow, kind: VButtonKind.text, onPressed: _busy ? null : () => _finish()),
      ]);
    }
    return CenteredPage(children: [
      const Center(child: VaultLogo(size: 40)),
      const SizedBox(height: 28),
      Text(_first == null ? l.pinTitle : l.pinRepeat, style: t.headline, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(_mismatch ? l.pinMismatch : l.pinSubtitle,
          style: t.subhead.copyWith(color: _mismatch ? context.colors.danger : null), textAlign: TextAlign.center),
      const SizedBox(height: 36),
      Center(child: DigitsInput(key: _inputKey, obscure: true, onCompleted: _entered, error: _mismatch)),
    ]);
  }
}
