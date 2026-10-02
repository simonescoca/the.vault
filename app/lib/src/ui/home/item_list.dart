// Middle column: search, "+" and the alphabetical list.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/favicon/favicon_service.dart';
import '../../core/model/item.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'home_controller.dart';
import 'item_icon.dart';

class ItemList extends StatefulWidget {
  const ItemList({super.key, required this.home, required this.favicons, required this.searchFocus, required this.onNew, required this.onSelect});
  final HomeController home;
  final FaviconService? favicons;
  final FocusNode searchFocus;
  final VoidCallback onNew;

  /// Selecting another entry (the screen asks before discarding an edit).
  final ValueChanged<String> onSelect;

  @override
  State<ItemList> createState() => _ItemListState();
}

class _ItemListState extends State<ItemList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.home.addListener(_sync);
  }

  void _sync() {
    if (widget.home.query != _search.text) _search.text = widget.home.query;
  }

  @override
  void dispose() {
    widget.home.removeListener(_sync);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l;
    final home = widget.home;
    final topPad = Platform.isMacOS ? 12.0 : 12.0;
    return Container(
      width: 300,
      color: c.bg,
      child: Column(children: [
        SizedBox(height: Platform.isMacOS ? 0 : 0),
        Stack(children: [
          if (Platform.isMacOS) const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
          Padding(
            padding: EdgeInsets.fromLTRB(12, topPad, 8, 10),
            child: Row(children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (node, e) {
                    if (e is KeyDownEvent || e is KeyRepeatEvent) {
                      if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                        home.moveSelection(1);
                        return KeyEventResult.handled;
                      }
                      if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                        home.moveSelection(-1);
                        return KeyEventResult.handled;
                      }
                      if (e.logicalKey == LogicalKeyboardKey.escape && _search.text.isNotEmpty) {
                        home.setQuery('');
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: VTextField(
                    controller: _search,
                    focusNode: widget.searchFocus,
                    hint: l.search,
                    dense: true,
                    prefix: Icon(Ic.search, size: 15, color: c.text3),
                    suffix: ListenableBuilder(
                      listenable: _search,
                      builder: (context, _) => _search.text.isEmpty
                          ? const SizedBox.shrink()
                          : VIconButton(icon: Ic.x, size: 14, box: 22, onPressed: () => home.setQuery('')),
                    ),
                    onChanged: home.setQuery,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              VIconButton(icon: Ic.plus, size: 18, box: 32, tooltip: l.newItem, onPressed: widget.onNew),
            ]),
          ),
        ]),
        Expanded(
          child: ListenableBuilder(
            listenable: home,
            builder: (context, _) {
              final items = home.visible;
              return Column(children: [
                if (home.section == Section.trash && items.isNotEmpty && home.query.isEmpty) _TrashHeader(home: home),
                Expanded(child: items.isEmpty ? _Empty(home: home) : _list(context, items)),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, List<Item> items) {
    final home = widget.home;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: items.length,
      itemExtent: 54,
      itemBuilder: (context, i) {
        final it = items[i];
        final subtitle = it.inTrash ? l.deletedOn(DateFormat.yMMMd(locale).format(it.trashedAt!)) : it.subtitle;
        return _Row(
          item: it,
          subtitle: subtitle,
          selected: it.id == home.selectedId && !(home.editing && home.draft!.isNew),
          favicons: widget.favicons,
          onTap: () => widget.onSelect(it.id),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.subtitle, required this.selected, required this.favicons, required this.onTap});
  final Item item;
  final String subtitle;
  final bool selected;
  final FaviconService? favicons;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Hover(
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? c.selected : (hovered ? c.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            ItemIcon(item: item, favicons: favicons),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: t.listTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.listSubtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (item.favorite && !item.inTrash) Icon(Icons.star_rounded, size: 13, color: c.text3),
          ]),
        ),
      ),
    );
  }
}

class _TrashHeader extends StatelessWidget {
  const _TrashHeader({required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(children: [
        const Spacer(),
        VButton(
          label: l.emptyTrashAction,
          kind: VButtonKind.text,
          icon: Ic.trash2,
          onPressed: () async {
            final n = home.vault.count(Section.trash);
            if (await confirm(context, title: l.emptyTrashAction, body: l.emptyTrashConfirm(n), confirmLabel: l.deleteForever, cancelLabel: l.cancel)) {
              home.vault.emptyTrash();
            }
          },
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final (icon, text) = home.query.isNotEmpty
        ? (Ic.search, l.noResults(home.query))
        : switch (home.section) {
            Section.all => (Ic.vault, l.emptyAll),
            Section.favorites => (Ic.star, l.emptyFavorites),
            Section.trash => (Ic.trash2, l.emptyTrash),
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 60),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 26, color: c.text3),
          const SizedBox(height: 12),
          Text(text, style: t.small.copyWith(color: c.text3, height: 1.5), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
