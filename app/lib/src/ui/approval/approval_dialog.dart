// "New access" dialog on a connected device (docs/SPEC.md §10).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/account/account_service.dart';
import '../../core/api/api_client.dart';
import '../../core/crypto/vault_crypto.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

String platformName(String p) => switch (p) {
      'macos' => 'macOS',
      'windows' => 'Windows',
      'linux' => 'Linux',
      'ios' => 'iPhone',
      'android' => 'Android',
      _ => p,
    };

Future<void> showApprovalDialog(BuildContext context, ApprovalInfo request) =>
    showVDialog<void>(context, (ctx) => _ApprovalDialog(request: request), dismissible: false);

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.request});
  final ApprovalInfo request;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

enum _Phase { waiting, code, busy, closed }

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late final ApprovalResponse _resp;
  _Phase _phase = _Phase.waiting;
  String? _code;
  String? _closedMessage;
  StreamSubscription<Map<String, dynamic>>? _events;

  @override
  void initState() {
    super.initState();
    final app = context.app;
    _resp = ApprovalResponse(app.crypto, app.session!.api, widget.request);
    _events = app.session!.approvalEvents.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'approval.closed' && e['approvalId'] == widget.request.id && _phase != _Phase.busy) {
        _close(context.l.approvalHandledElsewhere);
      }
    });
    // Translations are available only after the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final l = context.l;
    try {
      final code = await _resp.start();
      if (!mounted) return;
      setState(() {
        _code = code;
        _phase = _Phase.code;
      });
    } on CryptoException {
      try {
        await _resp.reject();
      } catch (_) {}
      _close(l.approvalTampered);
    } on ApiException catch (e) {
      _close(e.status == 409 ? l.approvalHandledElsewhere : l.approvalExpired);
    } on ApprovalClosed catch (e) {
      _close(e.state == 'expired' ? l.approvalExpired : l.approvalHandledElsewhere);
    } catch (_) {
      _close(l.serverUnreachable);
    }
  }

  void _close(String message) {
    if (!mounted || _phase == _Phase.closed) return;
    setState(() {
      _phase = _Phase.closed;
      _closedMessage = message;
    });
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _approve() async {
    final app = context.app;
    final l = context.l;
    setState(() => _phase = _Phase.busy);
    try {
      await _resp.approve(vaultKey: app.vaultKey, userId: app.identity!.userId);
      if (!mounted) return;
      context.toasts.show(l.deviceApproved);
      Navigator.of(context).pop();
    } catch (_) {
      _close(l.approvalExpired);
    }
  }

  Future<void> _reject() async {
    setState(() => _phase = _Phase.busy);
    try {
      await _resp.reject();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final r = widget.request;
    return VPanel(
      width: 440,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Ic.monitorSmartphone, size: 20, color: c.text),
          const SizedBox(width: 10),
          Text(l.newAccessTitle, style: t.section.copyWith(fontSize: 16)),
        ]),
        const SizedBox(height: 12),
        Text(l.newAccessBody(r.deviceName, platformName(r.devicePlatform)), style: t.body),
        const SizedBox(height: 22),
        if (_phase == _Phase.closed)
          Text(_closedMessage ?? '', style: t.body.copyWith(color: c.text2), textAlign: TextAlign.center)
        else if (_code == null)
          Column(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.text2)),
            const SizedBox(height: 10),
            Text(l.waitingForDevice, style: t.small),
          ])
        else ...[
          Text(l.verificationCode, style: t.small, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('${_code!.substring(0, 3)} ${_code!.substring(3)}',
              style: t.monoLarge.copyWith(fontSize: 34, letterSpacing: 4), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(l.newAccessCodeHint, style: t.small, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(l.newAccessWarning, style: t.small.copyWith(color: c.text3), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        if (_phase != _Phase.closed)
          DialogActions(children: [
            VButton(label: l.reject, kind: VButtonKind.secondary, onPressed: _phase == _Phase.busy ? null : _reject),
            VButton(label: l.approve, busy: _phase == _Phase.busy, onPressed: _phase == _Phase.code ? _approve : null),
          ]),
      ]),
    );
  }
}
