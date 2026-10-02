// The locked vault (docs/SPEC.md §3).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/lock_service.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/digits_input.dart';
import '../widgets/logo.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _biometrics = false;
  bool _showPin = false;
  bool _busy = false;
  String? _message;
  bool _error = false;
  int _wait = 0;
  Timer? _waitTimer;
  final _pinKey = GlobalKey<DigitsInputState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final app = context.app;
    final bio = await app.lock.canUseBiometrics();
    final wait = await app.lock.lockoutRemaining();
    if (!mounted) return;
    setState(() {
      _biometrics = bio;
      _showPin = !bio;
    });
    if (wait > 0) _startWait(wait);
    if (bio) await _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    setState(() => _busy = true);
    final ok = await context.app.unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _showPin = true;
    });
  }

  void _startWait(int seconds) {
    _waitTimer?.cancel();
    setState(() => _wait = seconds);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) {
        t.cancel();
        setState(() => _message = null);
      }
    });
  }

  Future<void> _pinEntered(String pin) async {
    setState(() => _busy = true);
    final l = context.l;
    final r = await context.app.unlockWithPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case PinOk():
      case PinWipe():
        return;
      case PinWrong(:final attemptsLeft, :final waitSeconds):
        setState(() {
          _error = true;
          _message = attemptsLeft == null ? l.pinWrong : l.pinAttemptsLeft(attemptsLeft);
        });
        _pinKey.currentState?.reject();
        if (waitSeconds > 0) _startWait(waitSeconds);
      case PinLockedOut(:final waitSeconds):
        _pinKey.currentState?.clear();
        _startWait(waitSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final app = context.app;
    final method = app.platform.biometricName;
    return CenteredPage(children: [
      const Center(child: VaultLogo(size: 56, filled: true)),
      const SizedBox(height: 26),
      Text(l.lockedTitle, style: t.headline, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(app.identity?.email ?? '', style: t.subhead, textAlign: TextAlign.center),
      const SizedBox(height: 36),
      if (_showPin) ...[
        Center(
          child: DigitsInput(
            key: _pinKey,
            obscure: true,
            enabled: _wait <= 0 && !_busy,
            error: _error,
            onCompleted: _pinEntered,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 20,
          child: Text(
            _wait > 0 ? l.pinWait(_wait) : (_message ?? ''),
            style: t.small.copyWith(color: _error || _wait > 0 ? c.danger : c.text2),
            textAlign: TextAlign.center,
          ),
        ),
        if (_biometrics) ...[
          const SizedBox(height: 12),
          Center(child: VButton(label: l.useMethod(method), kind: VButtonKind.text, icon: Ic.fingerprint, onPressed: _busy ? null : _tryBiometrics)),
        ],
      ] else ...[
        Center(
          child: VButton(
            label: l.unlock,
            large: true,
            icon: method == 'Touch ID' ? Ic.fingerprint : Ic.scanFace,
            busy: _busy,
            onPressed: _tryBiometrics,
          ),
        ),
        const SizedBox(height: 10),
        Center(child: VButton(label: l.usePin, kind: VButtonKind.text, onPressed: () => setState(() => _showPin = true))),
      ],
      ValueListenableBuilder<int>(
        valueListenable: app.pendingApprovalCount,
        builder: (context, n, _) => n == 0
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Ic.monitorSmartphone, size: 15, color: c.text2),
                  const SizedBox(width: 6),
                  Text(l.pendingRequests(n), style: t.small),
                ]),
              ),
      ),
    ]);
  }
}
