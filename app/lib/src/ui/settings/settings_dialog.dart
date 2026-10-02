// Settings (docs/SPEC.md §11).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/lock_service.dart';
import '../../app/settings.dart';
import '../../core/api/api_client.dart';
import '../../core/backup/backup_service.dart';
import '../../core/crypto/recovery_code.dart';
import '../app.dart';
import '../approval/approval_dialog.dart';
import '../icons.dart';
import '../onboarding/kit_pdf.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/digits_input.dart';

Future<void> showSettingsDialog(BuildContext context) => showVDialog<void>(context, (ctx) => const _SettingsDialog());

enum _Tab { general, security, devices, backup, account }

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _Tab _tab = _Tab.general;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final tabs = {
      _Tab.general: (Ic.sun, l.settingsGeneral),
      _Tab.security: (Ic.shield, l.settingsSecurity),
      _Tab.devices: (Ic.laptop, l.settingsDevices),
      _Tab.backup: (Ic.hardDrive, l.settingsBackup),
      _Tab.account: (Ic.user, l.settingsAccount),
    };
    return VPanel(
      width: 720,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 500,
        child: Row(children: [
          Container(
            width: 190,
            decoration: BoxDecoration(color: c.sidebar, borderRadius: const BorderRadius.horizontal(left: Radius.circular(14))),
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(10, 0, 0, 14), child: Text(l.settings, style: context.text.section.copyWith(fontSize: 15))),
              for (final e in tabs.entries)
                _TabTile(icon: e.value.$1, label: e.value.$2, selected: _tab == e.key, onTap: () => setState(() => _tab = e.key)),
            ]),
          ),
          const VDivider(vertical: true),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  child: switch (_tab) {
                    _Tab.general => const _General(),
                    _Tab.security => const _Security(),
                    _Tab.devices => const _Devices(),
                    _Tab.backup => const _Backup(),
                    _Tab.account => const _Account(),
                  },
                ),
              ),
              Positioned(top: 10, right: 10, child: VIconButton(icon: Ic.x, tooltip: l.close, onPressed: () => Navigator.of(context).pop())),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TabTile extends StatelessWidget {
  const _TabTile({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (context, h) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: selected ? c.selected : (h ? c.hover : Colors.transparent), borderRadius: BorderRadius.circular(7)),
          child: Row(children: [
            Icon(icon, size: 15, color: selected ? c.text : c.text2),
            const SizedBox(width: 10),
            Text(label, style: context.text.sidebar.copyWith(color: selected ? c.text : c.text2)),
          ]),
        ),
      ),
    );
  }
}

/// A labelled setting row.
class _Line extends StatelessWidget {
  const _Line({required this.label, this.hint, required this.child});
  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.body),
            if (hint != null) Text(hint!, style: t.small.copyWith(color: context.colors.text3)),
          ]),
        ),
        const SizedBox(width: 16),
        child,
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(text, style: context.text.section.copyWith(fontSize: 16)));
}

// ---------------------------------------------------------------------- general

class _General extends StatelessWidget {
  const _General();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = context.app.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Title(l.settingsGeneral),
        _Line(
          label: l.appearance,
          child: VSegmented<ThemeMode>(
            value: s.themeMode,
            options: [(ThemeMode.system, l.themeSystem), (ThemeMode.light, l.themeLight), (ThemeMode.dark, l.themeDark)],
            onChanged: (v) {
              s.themeMode = v;
              s.save();
            },
          ),
        ),
        _Line(
          label: l.language,
          child: VSegmented<String>(
            value: s.language,
            options: [('system', l.languageSystem), ('it', 'Italiano'), ('en', 'English')],
            onChanged: (v) {
              s.language = v;
              s.save();
            },
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------------- security

class _Security extends StatefulWidget {
  const _Security();

  @override
  State<_Security> createState() => _SecurityState();
}

class _SecurityState extends State<_Security> {
  bool? _available;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.app;
    final a = await app.platform.biometricsAvailable();
    final e = await app.lock.biometricsEnabled();
    if (!mounted) return;
    setState(() {
      _available = a;
      _enabled = e;
    });
  }

  Future<void> _toggleBio(bool v) async {
    final app = context.app;
    if (v) {
      final ok = await app.platform.authenticate(context.l.biometricReason);
      if (!ok) return;
    }
    await app.lock.setBiometricsEnabled(v);
    if (mounted) setState(() => _enabled = v);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final app = context.app;
    final s = app.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Title(l.settingsSecurity),
        _Line(
          label: l.unlockWith(app.platform.biometricName),
          hint: _available == false ? l.biometricsUnavailable : null,
          child: VSwitch(value: _enabled && _available == true, onChanged: _available == true ? _toggleBio : null),
        ),
        _Line(label: l.changePin, child: VButton(label: l.changePin, kind: VButtonKind.secondary, onPressed: () => _changePin(context))),
        _Line(
          label: l.autoLock,
          child: VSegmented<int>(
            value: s.autoLockMinutes,
            options: [for (final m in AppSettings.autoLockChoices) (m, l.minutesShort(m))],
            onChanged: (v) {
              s.autoLockMinutes = v;
              s.save();
              app.registerActivity();
            },
          ),
        ),
        _Line(
          label: l.clipboardClear,
          child: VSegmented<int>(
            value: s.clipboardSeconds,
            options: [
              for (final x in AppSettings.clipboardChoices)
                (x, x == 0 ? l.never : (x < 60 ? l.secondsShort(x) : l.minutesShort(x ~/ 60))),
            ],
            onChanged: (v) {
              s.clipboardSeconds = v;
              s.save();
            },
          ),
        ),
        _Line(
          label: l.emergencyKit,
          child: VButton(label: l.newEmergencyCode, kind: VButtonKind.secondary, onPressed: () => _newKit(context)),
        ),
      ]),
    );
  }

  Future<void> _changePin(BuildContext context) => showVDialog<void>(context, (ctx) => const _ChangePinDialog());

  Future<void> _newKit(BuildContext context) async {
    final l = context.l;
    final app = context.app;
    if (!await confirm(context, title: l.newEmergencyCode, body: l.newEmergencyCodeConfirm, confirmLabel: l.continueLabel, cancelLabel: l.cancel, danger: false)) {
      return;
    }
    try {
      final code = await app.account.replaceRecovery(app.identity!, app.vaultKey);
      if (context.mounted) await showVDialog<void>(context, (ctx) => _KitDialog(code: code), dismissible: false);
    } catch (e) {
      if (context.mounted) context.toasts.show(e is NetworkException ? l.offlineError : l.genericError('$e'));
    }
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();
  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  int _step = 0; // 0 current, 1 new, 2 repeat
  String? _new;
  String? _message;
  final _key = GlobalKey<DigitsInputState>();

  Future<void> _entered(String pin) async {
    final app = context.app;
    final l = context.l;
    switch (_step) {
      case 0:
        final r = await app.lock.verifyPin(pin);
        if (r is PinOk) {
          setState(() {
            _step = 1;
            _message = null;
          });
          _key.currentState?.clear();
        } else if (r is PinWipe) {
          if (mounted) Navigator.of(context).pop();
          await app.wipeDevice(tellServer: false);
        } else {
          setState(() => _message = r is PinWrong && r.attemptsLeft != null ? l.pinAttemptsLeft(r.attemptsLeft!) : l.pinWrong);
          _key.currentState?.reject();
        }
      case 1:
        _new = pin;
        setState(() => _step = 2);
        _key.currentState?.clear();
      case 2:
        if (pin != _new) {
          setState(() {
            _step = 1;
            _message = l.pinMismatch;
          });
          _key.currentState?.reject();
          return;
        }
        await app.lock.setPin(pin);
        if (!mounted) return;
        context.toasts.show(l.pinChanged);
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    return VPanel(
      width: 380,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text([l.currentPin, l.newPin, l.pinRepeat][_step], style: t.section.copyWith(fontSize: 15)),
        const SizedBox(height: 22),
        DigitsInput(key: _key, obscure: true, onCompleted: _entered, error: _message != null),
        const SizedBox(height: 14),
        SizedBox(height: 18, child: Text(_message ?? '', style: t.small.copyWith(color: context.colors.danger))),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: VButton(label: l.cancel, kind: VButtonKind.secondary, onPressed: () => Navigator.of(context).pop())),
      ]),
    );
  }
}

class _KitDialog extends StatelessWidget {
  const _KitDialog({required this.code});
  final RecoveryCode code;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final app = context.app;
    return VPanel(
      width: 470,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.kitTitle, style: t.section.copyWith(fontSize: 16)),
        const SizedBox(height: 8),
        Text(l.kitSubtitle, style: t.small),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.inputBorder)),
          child: SelectableText(code.formatted, textAlign: TextAlign.center, style: t.monoLarge),
        ),
        const SizedBox(height: 18),
        Row(children: [
          VButton(
            label: l.kitSavePdf,
            kind: VButtonKind.secondary,
            icon: Ic.fileDown,
            onPressed: () async {
              final bytes = await buildKitPdf(l: l, code: code.formatted, email: app.identity!.email, server: app.identity!.server.host, date: DateTime.now());
              final path = await app.platform.saveFileDialog('The Vault - ${l.kitTitle}.pdf', extensions: ['pdf']);
              if (path != null) {
                await File(path).writeAsBytes(bytes);
                if (context.mounted) context.toasts.show(l.kitSaved);
              }
            },
          ),
          const SizedBox(width: 8),
          VButton(
            label: l.copy,
            kind: VButtonKind.secondary,
            icon: Ic.copy,
            onPressed: () {
              app.copy(code.formatted);
              context.toasts.show(l.copied);
            },
          ),
          const Spacer(),
          VButton(label: l.done, onPressed: () => Navigator.of(context).pop()),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------- devices

class _Devices extends StatefulWidget {
  const _Devices();
  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  Future<List<DeviceInfo>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
    context.app.session!.devicesVersion.addListener(_reload);
  }

  @override
  void deactivate() {
    context.app.session?.devicesVersion.removeListener(_reload);
    super.deactivate();
  }

  void _reload() {
    if (!mounted) return;
    final future = context.app.session!.api.devices();
    setState(() {
      _future = future;
    });
  }

  Future<void> _rename(DeviceInfo d) async {
    final l = context.l;
    final ctrl = TextEditingController(text: d.name);
    final name = await showVDialog<String>(context, (ctx) => VPanel(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.rename, style: ctx.text.section.copyWith(fontSize: 15)),
            const SizedBox(height: 14),
            VTextField(controller: ctrl, hint: l.deviceName, autofocus: true, onSubmitted: (v) => Navigator.of(ctx).pop(v)),
            const SizedBox(height: 16),
            DialogActions(children: [
              VButton(label: l.cancel, kind: VButtonKind.secondary, onPressed: () => Navigator.of(ctx).pop()),
              VButton(label: l.save, onPressed: () => Navigator.of(ctx).pop(ctrl.text)),
            ]),
          ]),
        ));
    if (name == null || name.trim().isEmpty || !mounted) return;
    final app = context.app;
    final toasts = context.toasts;
    try {
      await app.session!.api.renameSelf(name.trim());
      app.identity!.deviceName = name.trim();
      _reload();
    } catch (e) {
      toasts.show(l.offlineError);
    }
  }

  Future<void> _disconnect(DeviceInfo d) async {
    final l = context.l;
    if (!await confirm(context, title: l.disconnect, body: l.disconnectConfirm(d.name), confirmLabel: l.disconnect, cancelLabel: l.cancel)) return;
    if (!mounted) return;
    try {
      await context.app.session!.api.revokeDevice(d.id);
      _reload();
    } catch (e) {
      if (mounted) context.toasts.show(l.offlineError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final locale = Localizations.localeOf(context).languageCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Title(l.settingsDevices),
      FutureBuilder<List<DeviceInfo>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Text(l.offlineError, style: t.small);
          if (!snap.hasData) return Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.text2)));
          final list = [...snap.data!]..sort((a, b) => a.current ? -1 : (b.current ? 1 : b.lastSeenAt.compareTo(a.lastSeenAt)));
          return Column(children: [
            for (final d in list)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: c.divider)),
                child: Row(children: [
                  Icon(d.platform == 'windows' ? Ic.monitor : (d.platform == 'ios' || d.platform == 'android' ? Ic.smartphone : Ic.laptop), size: 20, color: c.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(d.name, style: t.bodyStrong, overflow: TextOverflow.ellipsis)),
                        if (d.current) ...[const SizedBox(width: 8), _Tag(l.thisDevice)],
                        if (d.status != 'active') ...[const SizedBox(width: 8), _Tag(l.pendingDevice)],
                      ]),
                      Text('${platformName(d.platform)} · ${l.lastSeen(DateFormat.yMMMd(locale).add_Hm().format(d.lastSeenAt))}', style: t.small),
                    ]),
                  ),
                  if (d.current)
                    VButton(label: l.rename, kind: VButtonKind.text, onPressed: () => _rename(d))
                  else
                    VButton(label: l.disconnect, kind: VButtonKind.text, onPressed: () => _disconnect(d)),
                ]),
              ),
          ]);
        },
      ),
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: context.colors.selected, borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: context.text.tiny.copyWith(color: context.colors.text2)),
      );
}

// ----------------------------------------------------------------------- backup

class _Backup extends StatelessWidget {
  const _Backup();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Title(l.settingsBackup),
      _Line(label: l.exportTitle.replaceAll('…', ''), hint: l.exportSubtitle,
          child: VButton(label: l.exportTitle, kind: VButtonKind.secondary, icon: Ic.download, onPressed: () => showVDialog<void>(context, (ctx) => const _ExportDialog()))),
      _Line(label: l.importTitle.replaceAll('…', ''), hint: l.importSubtitle,
          child: VButton(label: l.importTitle, kind: VButtonKind.secondary, icon: Ic.upload, onPressed: () => _import(context))),
    ]);
  }

  Future<void> _import(BuildContext context) async {
    final path = await context.app.platform.pickFile(extensions: ['thevault']);
    if (path == null || !context.mounted) return;
    await showVDialog<void>(context, (ctx) => _ImportDialog(path: path));
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    final l = context.l;
    final app = context.app;
    if (_a.text.length < 10) return setState(() => _error = l.passwordTooShort);
    if (_a.text != _b.text) return setState(() => _error = l.passwordsDontMatch);
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final path = await app.platform.saveFileDialog('TheVault-Backup-$date.thevault', extensions: ['thevault']);
    if (path == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackupService(app.crypto).export(app.session!.vault, path, _a.text, appVersion: app.version);
      if (!mounted) return;
      context.toasts.show(l.exportDone);
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = l.genericError('$e');
      });
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    return VPanel(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.exportTitle.replaceAll('…', ''), style: t.section.copyWith(fontSize: 15)),
        const SizedBox(height: 6),
        Text(l.exportSubtitle, style: t.small),
        const SizedBox(height: 16),
        VTextField(controller: _a, hint: l.exportPassword, obscure: true, autofocus: true),
        const SizedBox(height: 8),
        VTextField(controller: _b, hint: l.exportPasswordRepeat, obscure: true, onSubmitted: (_) => _go(), error: _error),
        const SizedBox(height: 18),
        DialogActions(children: [
          VButton(label: l.cancel, kind: VButtonKind.secondary, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          VButton(label: _busy ? l.exporting : l.exportTitle.replaceAll('…', ''), busy: _busy, onPressed: _go),
        ]),
      ]),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.path});
  final String path;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;
  BackupSummary? _summary;

  Future<void> _go() async {
    final l = context.l;
    final app = context.app;
    final svc = BackupService(app.crypto);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_summary == null) {
        final s = await svc.inspect(widget.path, _pw.text);
        setState(() {
          _summary = s;
          _busy = false;
        });
        return;
      }
      final n = await svc.import(app.session!.vault, widget.path, _pw.text, app.openDir);
      if (!mounted) return;
      context.toasts.show(l.importDone(n));
      Navigator.of(context).pop();
    } on BackupException {
      setState(() {
        _busy = false;
        _error = l.importWrongPassword;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = l.genericError('$e');
      });
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    return VPanel(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.importTitle.replaceAll('…', ''), style: t.section.copyWith(fontSize: 15)),
        const SizedBox(height: 6),
        Text(widget.path.split(Platform.pathSeparator).last, style: t.small),
        const SizedBox(height: 16),
        if (_summary == null)
          VTextField(controller: _pw, hint: l.importPassword, obscure: true, autofocus: true, onSubmitted: (_) => _go(), error: _error)
        else
          Text(l.importSummary(_summary!.items, _summary!.files), style: t.body),
        if (_summary != null && _error != null) Text(_error!, style: t.small.copyWith(color: context.colors.danger)),
        const SizedBox(height: 18),
        DialogActions(children: [
          VButton(label: l.cancel, kind: VButtonKind.secondary, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          VButton(label: _summary == null ? l.continueLabel : (_busy ? l.importing : l.importTitle.replaceAll('…', '')), busy: _busy, onPressed: _go),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------- account

class _Account extends StatelessWidget {
  const _Account();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final app = context.app;
    final id = app.identity!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Title(l.settingsAccount),
      _Line(label: l.accountEmail, child: Text(id.email, style: context.text.value)),
      _Line(label: l.accountServer, child: Text(id.server.host, style: context.text.value)),
      _Line(label: l.version, child: Text(app.version, style: context.text.value)),
      const SizedBox(height: 10),
      VButton(
        label: l.signOut,
        kind: VButtonKind.danger,
        icon: Ic.logOut,
        onPressed: () async {
          if (await confirm(context, title: l.signOut, body: l.signOutConfirm, confirmLabel: l.signOut, cancelLabel: l.cancel)) {
            if (context.mounted) Navigator.of(context).pop();
            await app.wipeDevice();
          }
        },
      ),
    ]);
  }
}
