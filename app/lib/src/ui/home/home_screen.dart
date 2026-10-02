// The unlocked vault: three columns, shortcuts, approvals of new devices.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/favicon/favicon_service.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../approval/approval_dialog.dart';
import '../detail/detail_edit.dart';
import '../detail/detail_view.dart';
import '../settings/settings_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/logo.dart';
import 'home_controller.dart';
import 'item_list.dart';
import 'sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.favicons});

  /// Injected in tests (null = created here).
  final FaviconService? favicons;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController home = HomeController(context.app.session!.vault);
  late final FaviconService favicons =
      widget.favicons ?? FaviconService(context.app.session!.db, home.vault.cache!, enabled: context.app.online);
  final _searchFocus = FocusNode();
  final _homeFocus = FocusNode(debugLabel: 'home');
  final _editKey = GlobalKey<DetailEditState>();
  StreamSubscription<ApprovalInfo>? _approvals;
  StreamSubscription<VaultNotice>? _notices;
  StreamSubscription<String>? _menu;
  bool _approvalOpen = false;
  final _approvalQueue = <ApprovalInfo>[];

  @override
  void initState() {
    super.initState();
    final app = context.app;
    home.setSection(Section.all);
    _approvals = app.approvalRequests.listen(_onApproval);
    _menu = app.platform.menuCommands.listen(_onMenu);
    // After unlocking, the keyboard focus belongs to the main window (shortcuts work right away).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _homeFocus.requestFocus();
    });
    FocusManager.instance.addListener(_keepKeyboard);
    _notices = home.vault.notices.listen((n) {
      if (n == VaultNotice.conflictCopy && mounted) context.toasts.show(context.l.conflictCopyNotice, duration: const Duration(seconds: 5));
    });
  }

  /// When the focused field goes away (a click elsewhere, the editor closing…) the keyboard would land outside
  /// the main window and the shortcuts would stop working: give it back to the window.
  void _keepKeyboard() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = FocusManager.instance.primaryFocus;
      if (mounted && (p == null || p is FocusScopeNode) && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _homeFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepKeyboard);
    _approvals?.cancel();
    _notices?.cancel();
    _menu?.cancel();
    home.dispose();
    if (widget.favicons == null) favicons.dispose();
    _searchFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- approvals

  Future<void> _onApproval(ApprovalInfo a) async {
    if (_approvalOpen) {
      if (!_approvalQueue.any((x) => x.id == a.id)) _approvalQueue.add(a);
      return;
    }
    _approvalOpen = true;
    await showApprovalDialog(context, a);
    _approvalOpen = false;
    if (_approvalQueue.isNotEmpty && mounted) _onApproval(_approvalQueue.removeAt(0));
  }

  // ------------------------------------------------------------ menu bar

  /// A command from the macOS menu bar. "Lock" always works; the others only when no dialog is open.
  void _onMenu(String command) {
    if (!mounted) return;
    if (command == 'lock') return context.app.lockNow();
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    switch (command) {
      case 'newItem':
        _new();
      case 'settings':
        _openSettings();
    }
  }

  // --------------------------------------------------------------- editing

  List<String> _suggestions(BuildContext context) {
    final l = context.l;
    return [l.suggestionWebsite, l.suggestionEmail, l.suggestionPassword];
  }

  /// Asks before losing unsaved changes. Returns true if it is fine to continue.
  Future<bool> _leaveEdit() async {
    if (!home.editing) return true;
    if (!home.dirty) {
      home.cancelEdit();
      return true;
    }
    final l = context.l;
    final ok = await confirm(context, title: l.discardTitle, confirmLabel: l.discard, cancelLabel: l.keepEditing);
    if (ok) home.cancelEdit();
    return ok;
  }

  Future<void> _new() async {
    if (!await _leaveEdit()) return;
    if (mounted) home.startNew(_suggestions(context));
  }

  Future<void> _select(String id) async {
    if (home.editing && home.selectedId == id && !home.draft!.isNew) return;
    if (!await _leaveEdit()) return;
    home.select(id);
  }

  Future<void> _save() async {
    if (!home.editing) return;
    final l = context.l;
    switch (home.save()) {
      case SaveResult.saved:
        context.toasts.show(l.saved, duration: const Duration(milliseconds: 1400));
      case SaveResult.needsTitle:
        _editKey.currentState?.needsTitle();
      case SaveResult.conflict:
        final choice = await showVDialog<String>(context, (ctx) => VPanel(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.editConflictTitle, style: ctx.text.section.copyWith(fontSize: 15)),
                const SizedBox(height: 8),
                Text(l.editConflictBody, style: ctx.text.body.copyWith(color: ctx.colors.text2)),
                const SizedBox(height: 20),
                DialogActions(children: [
                  VButton(label: l.cancel, kind: VButtonKind.text, onPressed: () => Navigator.of(ctx).pop()),
                  VButton(label: l.keepBoth, kind: VButtonKind.secondary, onPressed: () => Navigator.of(ctx).pop('both')),
                  VButton(label: l.overwrite, onPressed: () => Navigator.of(ctx).pop('overwrite')),
                ]),
              ]),
            ));
        if (choice == 'overwrite') home.save(force: true);
        if (choice == 'both') home.save(asCopy: true);
    }
  }

  Future<void> _cancel() async {
    await _leaveEdit();
  }

  void _openSettings() async {
    if (!await _leaveEdit()) return;
    if (mounted) await showSettingsDialog(context);
  }

  // ------------------------------------------------------------- shortcuts

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final mac = Platform.isMacOS;
    SingleActivator k(LogicalKeyboardKey key) => SingleActivator(key, meta: mac, control: !mac);
    return {
      k(LogicalKeyboardKey.keyN): _new,
      k(LogicalKeyboardKey.keyF): () => _searchFocus.requestFocus(),
      k(LogicalKeyboardKey.keyE): () {
        if (!home.editing) home.startEdit();
      },
      k(LogicalKeyboardKey.keyS): _save,
      k(LogicalKeyboardKey.comma): _openSettings,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (home.editing) {
          _cancel();
        } else if (home.query.isNotEmpty) {
          home.setQuery('');
        }
      },
      if (mac) const SingleActivator(LogicalKeyboardKey.backspace, meta: true): _trashSelected,
      if (!mac) const SingleActivator(LogicalKeyboardKey.delete): _trashSelected,
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        if (!home.editing) home.moveSelection(1);
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        if (!home.editing) home.moveSelection(-1);
      },
    };
  }

  void _trashSelected() {
    final it = home.selected;
    if (home.editing || it == null || it.inTrash) return;
    moveToTrashWithUndo(context, home.vault, it);
  }

  // -------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        focusNode: _homeFocus,
        autofocus: true,
        skipTraversal: true,
        child: Container(
          color: c.bg,
          child: Row(children: [
            Sidebar(home: home, onSettings: _openSettings),
            const VDivider(vertical: true),
            ItemList(home: home, favicons: favicons, searchFocus: _searchFocus, onNew: _new, onSelect: _select),
            const VDivider(vertical: true),
            Expanded(
              child: ListenableBuilder(
                listenable: home,
                builder: (context, _) {
                  Widget child;
                  if (home.editing) {
                    child = DetailEdit(key: _editKey, home: home, onSave: _save, onCancel: _cancel);
                  } else if (home.selected != null) {
                    child = DetailView(key: ValueKey(home.selected!.id), item: home.selected!, vault: home.vault, onEdit: home.startEdit);
                  } else {
                    child = const _NoSelection();
                  }
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: KeyedSubtree(key: ValueKey('${home.editing}-${home.draft?.originalId}-${home.selectedId}'), child: child),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      const DetailHeader(children: []),
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            VaultLogo(size: 56, color: c.text3.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(context.l.selectItem, style: context.text.small.copyWith(color: c.text3)),
          ]),
        ),
      ),
    ]);
  }
}
