// Left column: sections, settings, lock and the sync status.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/sync/sync_engine.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_controller.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.home, required this.onSettings});
  final HomeController home;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l;
    final vault = home.vault;
    final top = Platform.isMacOS ? 48.0 : 14.0;
    return Container(
      width: 220,
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Platform.isMacOS) SizedBox(height: top, child: const DragToMoveArea(child: SizedBox.expand())) else SizedBox(height: top),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ListenableBuilder(
              listenable: home,
              builder: (context, _) => Column(children: [
                _SectionTile(icon: Ic.layers, label: l.sectionAll, count: vault.count(Section.all), selected: home.section == Section.all, onTap: () => home.setSection(Section.all)),
                _SectionTile(icon: Ic.star, label: l.sectionFavorites, count: vault.count(Section.favorites), selected: home.section == Section.favorites, onTap: () => home.setSection(Section.favorites)),
                _SectionTile(icon: Ic.trash2, label: l.sectionTrash, count: vault.count(Section.trash), selected: home.section == Section.trash, onTap: () => home.setSection(Section.trash)),
              ]),
            ),
          ),
          const Spacer(),
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 4), child: _SyncStatus(engine: vault.sync, db: vault)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Row(children: [
              Expanded(child: _SectionTile(icon: Ic.settings, label: l.settings, selected: false, onTap: onSettings)),
              VIconButton(icon: Ic.lock, tooltip: l.lockNow, onPressed: () => context.app.lockNow()),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.icon, required this.label, this.count, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? c.selected : (hovered ? c.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: selected ? c.text : c.text2),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: t.sidebar.copyWith(color: selected ? c.text : c.text2), overflow: TextOverflow.ellipsis)),
            if (count != null && count! > 0) Text('$count', style: t.small.copyWith(color: c.text3)),
          ]),
        ),
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.engine, required this.db});
  final SyncEngine engine;
  final VaultController db;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final l = context.l;
    return ListenableBuilder(
      listenable: Listenable.merge([engine.state, db]),
      builder: (context, _) {
        final pending = db.db.pendingCount;
        final (icon, label, tip) = switch (engine.state.value) {
          SyncState.syncing => (Ic.refreshCw, l.syncing, null),
          SyncState.offline => (Ic.cloudOff, l.syncOffline, l.syncOfflineHint),
          SyncState.error => (Ic.triangleAlert, l.syncError, engine.lastError?.toString()),
          SyncState.idle => pending > 0 ? (Ic.cloud, l.pendingChanges(pending), null) : (Ic.circleCheck, l.syncOk, null),
        };
        final row = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 14, color: engine.state.value == SyncState.error ? c.danger : c.text3),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: t.small.copyWith(color: c.text3), overflow: TextOverflow.ellipsis)),
          ]),
        );
        return tip == null ? row : Tooltip(message: tip, child: row);
      },
    );
  }
}
