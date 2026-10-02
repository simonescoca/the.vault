// First access of a device (docs/SPEC.md §2).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/account/account_service.dart';
import '../../core/account/identity.dart';
import '../../core/api/api_client.dart';
import '../../core/crypto/recovery_code.dart';
import '../../core/crypto/vault_crypto.dart';
import '../../core/model/text_utils.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/digits_input.dart';
import '../widgets/logo.dart';
import 'kit_pdf.dart';
import 'pin_setup.dart';

enum _Step { welcome, server, email, code, creating, kit, approval, recovery, pin }

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.welcome;
  bool _busy = false;
  String? _error;

  final _serverCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _recoveryCtrl = TextEditingController();
  final _codeKey = GlobalKey<DigitsInputState>();

  Uri? _server;
  Identity? _identity;
  SecureKey? _vaultKey;
  RecoveryCode? _kitCode;
  bool _kitConfirmed = false;

  ApprovalRequest? _approval;
  StreamSubscription<ApprovalProgress>? _approvalSub;
  String? _sas;
  String? _approvalEnded;

  Timer? _resendTimer;
  int _resendIn = 0;

  AccountService get _account => context.app.account;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _emailCtrl.dispose();
    _recoveryCtrl.dispose();
    _resendTimer?.cancel();
    _approvalSub?.cancel();
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        _step = s;
        _error = null;
        _busy = false;
      });

  String _errorText(Object e) {
    final l = context.l;
    if (e is NetworkException) return l.serverUnreachable;
    if (e is ApiException) {
      switch (e.code) {
        case 'rate_limited':
          return l.tooManyRequests(e.retryAfter ?? 60);
        case 'mail_failed':
          return l.mailFailed;
        case 'invalid_email':
          return l.emailInvalid;
        case 'otp_expired':
          return l.codeExpired;
        case 'otp_invalid':
          return l.codeWrong((e.body['attemptsLeft'] as num?)?.toInt() ?? 0);
        case 'recovery_invalid':
          return l.recoveryWrong;
      }
      return l.genericError(e.message.isEmpty ? e.code : e.message);
    }
    if (e is CryptoException) return l.recoveryWrong;
    return l.genericError('$e');
  }

  // ------------------------------------------------------------------ actions

  Future<void> _checkServer() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _server = await _account.checkServer(_serverCtrl.text);
      _go(_Step.email);
    } on FormatException {
      setState(() => _error = context.l.serverInvalid);
    } on ApiException {
      setState(() => _error = context.l.serverNotVault);
    } catch (_) {
      setState(() => _error = context.l.serverUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (!isEmail(_emailCtrl.text)) {
      setState(() => _error = context.l.emailInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.requestCode(_server!, _emailCtrl.text, deviceName: context.app.platform.defaultDeviceName());
      if (_step != _Step.code) _go(_Step.code);
      _startResendTimer();
    } catch (e) {
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verify(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.app;
    try {
      final id = _identity = await _account.verifyCode(
        server: _server!,
        email: _emailCtrl.text,
        code: code,
        deviceName: app.platform.defaultDeviceName(),
        platform: app.platform.platform,
      );
      if (id.status == 'setup') {
        await _createVault();
      } else {
        _startApproval();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(e);
      });
      _codeKey.currentState?.reject();
    }
  }

  Future<void> _createVault() async {
    _go(_Step.creating);
    try {
      final r = await _account.createVault(_identity!);
      _vaultKey = r.vaultKey;
      _kitCode = r.code;
      _go(_Step.kit);
    } on AlreadyInitialized {
      _startApproval();
    } catch (e) {
      _go(_Step.email);
      setState(() => _error = _errorText(e));
    }
  }

  void _startApproval() {
    _go(_Step.approval);
    _sas = null;
    _approvalEnded = null;
    final req = _approval = _account.requestApproval(_identity!);
    _approvalSub?.cancel();
    _approvalSub = req.progress.listen((p) {
      if (!mounted) return;
      switch (p) {
        case ApprovalWaiting():
          break;
        case ApprovalCode(:final code):
          setState(() => _sas = code);
        case ApprovalGranted(:final vaultKey):
          _vaultKey = vaultKey;
          _go(_Step.pin);
        case ApprovalEnded(:final state):
          setState(() => _approvalEnded = state);
      }
    });
  }

  Future<void> _useRecovery() async {
    final code = RecoveryCode.tryParse(_recoveryCtrl.text);
    if (code == null) {
      setState(() => _error = context.l.recoveryFormat);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _vaultKey = await _account.useRecoveryCode(_identity!, code);
      _go(_Step.pin);
    } catch (e) {
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKitPdf() async {
    final app = context.app;
    final l = context.l;
    final bytes = await buildKitPdf(
      l: l,
      code: _kitCode!.formatted,
      email: _identity!.email,
      server: _identity!.server.host,
      date: DateTime.now(),
    );
    final path = await app.platform.saveFileDialog('The Vault - ${l.kitTitle}.pdf', extensions: ['pdf']);
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
    if (mounted) context.toasts.show(l.kitSaved);
  }

  Future<void> _finish(String pin) async {
    final app = context.app;
    await app.lock.setPin(pin);
    await app.onboardingDone(_identity!, _vaultKey!);
  }

  // --------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(key: ValueKey(_step), child: _page(context)),
    );
  }

  Widget _back(_Step to) => VButton(label: context.l.back, kind: VButtonKind.text, icon: Ic.chevronLeft, onPressed: () => _go(to));

  Widget _header(String title, String subtitle, {bool logo = true}) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (logo) ...[const Center(child: VaultLogo(size: 40)), const SizedBox(height: 28)],
        Text(title, style: t.headline, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(subtitle, style: t.subhead, textAlign: TextAlign.center),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget? _errorLine() => _error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: context.text.small.copyWith(color: context.colors.danger), textAlign: TextAlign.center),
        );

  Widget _page(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    switch (_step) {
      case _Step.welcome:
        return CenteredPage(children: [
          const Center(child: VaultLogo(size: 72, filled: true)),
          const SizedBox(height: 28),
          Text(l.appName, style: t.title.copyWith(fontSize: 32), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l.tagline, style: t.subhead, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          VButton(label: l.start, large: true, expand: true, onPressed: () => _go(_Step.server)),
        ]);

      case _Step.server:
        return CenteredPage(top: _back(_Step.welcome), children: [
          _header(l.serverTitle, l.serverSubtitle),
          VTextField(
            controller: _serverCtrl,
            hint: l.serverHint,
            autofocus: true,
            mono: true,
            onSubmitted: (_) => _checkServer(),
            keyboardType: TextInputType.url,
          ),
          ?_errorLine(),
          const SizedBox(height: 20),
          VButton(label: l.continueLabel, large: true, expand: true, busy: _busy, onPressed: _checkServer),
        ]);

      case _Step.email:
        return CenteredPage(top: _back(_Step.server), children: [
          _header(l.emailTitle, l.emailSubtitle),
          VTextField(
            controller: _emailCtrl,
            hint: l.emailHint,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _sendCode(),
          ),
          ?_errorLine(),
          const SizedBox(height: 20),
          VButton(label: l.sendCode, large: true, expand: true, busy: _busy, onPressed: _sendCode),
        ]);

      case _Step.code:
        return CenteredPage(top: _back(_Step.email), children: [
          _header(l.codeTitle, l.codeSubtitle(_emailCtrl.text.trim())),
          Center(child: DigitsInput(key: _codeKey, onCompleted: _verify, enabled: !_busy, error: _error != null)),
          ?_errorLine(),
          const SizedBox(height: 28),
          Center(
            child: _busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.text2))
                : VButton(
                    label: _resendIn > 0 ? l.resendIn(_resendIn) : l.resendCode,
                    kind: VButtonKind.text,
                    onPressed: _resendIn > 0 ? null : _sendCode,
                  ),
          ),
        ]);

      case _Step.creating:
        return CenteredPage(children: [
          const Center(child: VaultLogo(size: 40)),
          const SizedBox(height: 28),
          Text(l.creatingVault, style: t.subhead, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.text2))),
        ]);

      case _Step.kit:
        final code = _kitCode!.formatted;
        return CenteredPage(width: 460, children: [
          Center(child: Icon(Ic.shieldCheck, size: 36, color: c.text)),
          const SizedBox(height: 22),
          Text(l.kitTitle, style: t.headline, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(l.kitSubtitle, style: t.subhead, textAlign: TextAlign.center),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.inputBorder)),
            child: SelectableText(code, textAlign: TextAlign.center, style: t.monoLarge),
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            VButton(label: l.kitSavePdf, kind: VButtonKind.secondary, icon: Ic.fileDown, onPressed: _saveKitPdf),
            const SizedBox(width: 8),
            VButton(
              label: l.copy,
              kind: VButtonKind.secondary,
              icon: Ic.copy,
              onPressed: () {
                context.app.copy(code);
                context.toasts.show(l.copied);
              },
            ),
          ]),
          const SizedBox(height: 26),
          GestureDetector(
            onTap: () => setState(() => _kitConfirmed = !_kitConfirmed),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(children: [
                _Check(value: _kitConfirmed),
                const SizedBox(width: 10),
                Expanded(child: Text(l.kitConfirm, style: t.body)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          VButton(label: l.continueLabel, large: true, expand: true, onPressed: _kitConfirmed ? () => _go(_Step.pin) : null),
        ]);

      case _Step.approval:
        final ended = _approvalEnded;
        return CenteredPage(children: [
          Center(child: Icon(Ic.monitorSmartphone, size: 36, color: c.text)),
          const SizedBox(height: 22),
          Text(l.approvalTitle, style: t.headline, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(_sas == null ? l.approvalSubtitle : l.approvalCodeHint, style: t.subhead, textAlign: TextAlign.center),
          const SizedBox(height: 30),
          if (ended != null) ...[
            Text(
              switch (ended) {
                'rejected' => l.approvalRejected,
                'expired' => l.approvalExpired,
                'paused' => l.approvalPaused,
                'invalid' => l.approvalInvalid,
                'offline' => l.serverUnreachable,
                _ => l.approvalExpired,
              },
              style: t.body.copyWith(color: c.danger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            VButton(label: l.retry, large: true, expand: true, onPressed: _startApproval),
          ] else if (_sas == null) ...[
            Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.text2))),
            const SizedBox(height: 12),
            Text(l.approvalWaiting, style: t.small, textAlign: TextAlign.center),
          ] else ...[
            Text(l.verificationCode, style: t.small, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('${_sas!.substring(0, 3)} ${_sas!.substring(3)}',
                style: t.monoLarge.copyWith(fontSize: 34, letterSpacing: 4), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 36),
          VButton(
            label: l.noOtherDevice,
            kind: VButtonKind.text,
            onPressed: () async {
              await _approvalSub?.cancel();
              await _approval?.cancel();
              _go(_Step.recovery);
            },
          ),
        ]);

      case _Step.recovery:
        return CenteredPage(top: _back(_Step.approval), width: 440, children: [
          _header(l.recoveryTitle, l.recoverySubtitle),
          VTextField(
            controller: _recoveryCtrl,
            hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
            autofocus: true,
            mono: true,
            textAlign: TextAlign.center,
            style: t.value.copyWith(fontSize: 16, letterSpacing: 1),
            onSubmitted: (_) => _useRecovery(),
          ),
          ?_errorLine(),
          const SizedBox(height: 20),
          VButton(label: l.openVault, large: true, expand: true, busy: _busy, onPressed: _useRecovery),
        ]);

      case _Step.pin:
        return PinAndBiometrics(onDone: _finish);
    }
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.value});
  final bool value;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: value ? c.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: value ? c.primary : c.text3, width: 1.4),
      ),
      child: value ? Icon(Ic.check, size: 13, color: c.onPrimary) : null,
    );
  }
}
