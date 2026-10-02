// Viewing an entry: side-by-side rows, eye toggle, click to copy, links, description, attachments.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/model/item.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'attachments.dart';

/// Width of the key column: as wide as the longest key, between 96 and 180 px.
double keyColumnWidth(BuildContext context, Iterable<String> keys) {
  final style = context.text.key;
  var w = 0.0;
  for (final k in keys) {
    final tp = TextPainter(text: TextSpan(text: k, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    w = max(w, tp.width);
  }
  return (w + 24).clamp(96.0, 180.0);
}

class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(children: [
        if (Platform.isMacOS) const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [const Spacer(), ...children]),
        ),
      ]),
    );
  }
}

class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.item, required this.vault, required this.onEdit});
  final Item item;
  final VaultController vault;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final keyW = keyColumnWidth(context, item.fields.map((f) => f.key));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DetailHeader(children: [
        if (!item.inTrash) ...[
          VIconButton(
            icon: item.favorite ? Icons.star_rounded : Ic.star,
            size: item.favorite ? 18 : 16,
            color: item.favorite ? c.text : null,
            tooltip: item.favorite ? l.removeFavorite : l.addFavorite,
            onPressed: () => vault.setFavorite(item.id, !item.favorite),
          ),
          const SizedBox(width: 6),
          VButton(label: l.edit, kind: VButtonKind.secondary, icon: Ic.pencil, onPressed: onEdit),
          const SizedBox(width: 4),
          Builder(
            builder: (ctx) => VIconButton(
              icon: Ic.ellipsis,
              tooltip: l.more,
              onPressed: () async {
                final box = ctx.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset(0, box.size.height + 4));
                final r = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(pos.dx - 140, pos.dy, pos.dx + box.size.width, pos.dy),
                  items: [PopupMenuItem(value: 'trash', height: 34, child: Text(l.moveToTrash))],
                );
                if (r == 'trash' && context.mounted) moveToTrashWithUndo(context, vault, item);
              },
            ),
          ),
        ],
      ]),
      if (item.inTrash) _TrashBanner(item: item, vault: vault),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 6, 40, 48),
          child: SelectionArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: t.title),
              const SizedBox(height: 22),
              for (final f in item.fields) FieldRow(item: item, field: f, keyWidth: keyW, vault: vault, readOnly: item.inTrash),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(item.description, style: t.description),
              ],
              if (item.files.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(l.attachments, style: t.small.copyWith(color: c.text3)),
                const SizedBox(height: 8),
                SelectionContainer.disabled(
                  child: Column(children: [for (final a in item.files) AttachmentTile(key: ValueKey(a.id), attachment: a, vault: vault)]),
                ),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

void moveToTrashWithUndo(BuildContext context, VaultController vault, Item item) {
  final l = context.l;
  vault.moveToTrash(item.id);
  context.toasts.show(l.movedToTrash, actionLabel: l.undo, onAction: () => vault.restore(item.id));
}

class _TrashBanner extends StatelessWidget {
  const _TrashBanner({required this.item, required this.vault});
  final Item item;
  final VaultController vault;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final t = context.text;
    return Container(
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 14),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(color: c.sidebar, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.divider)),
      child: Row(children: [
        Icon(Ic.trash2, size: 15, color: c.text2),
        const SizedBox(width: 8),
        Expanded(child: Text(l.inTrashBanner, style: t.body.copyWith(color: c.text2))),
        VButton(
          label: l.restore,
          kind: VButtonKind.secondary,
          icon: Ic.rotateCcw,
          onPressed: () {
            vault.restore(item.id);
            context.toasts.show(l.restored);
          },
        ),
        const SizedBox(width: 6),
        VButton(
          label: l.deleteForever,
          kind: VButtonKind.danger,
          onPressed: () async {
            if (await confirm(context,
                title: l.deleteForever, body: l.deleteForeverConfirm(item.title), confirmLabel: l.deleteForever, cancelLabel: l.cancel)) {
              vault.deleteForever(item.id);
            }
          },
        ),
      ]),
    );
  }
}

/// One key/value row in view mode.
class FieldRow extends StatefulWidget {
  const FieldRow({super.key, required this.item, required this.field, required this.keyWidth, required this.vault, this.readOnly = false});
  final Item item;
  final Field field;
  final double keyWidth;
  final VaultController vault;
  final bool readOnly;

  @override
  State<FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<FieldRow> {
  bool _copied = false;
  Timer? _t;

  Field get f => widget.field;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _copy(String text) {
    context.app.copy(text);
    context.toasts.show(context.l.copied, duration: const Duration(milliseconds: 1400));
    setState(() => _copied = true);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _toggleHidden() => widget.vault.setHidden(widget.item.id, f.id, !f.hidden);

  void _menu(Offset pos, Uri? url) async {
    final l = context.l;
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'copy', height: 34, child: Text(f.link != null ? l.copyText : l.copy)),
        if (url != null) PopupMenuItem(value: 'copyLink', height: 34, child: Text(l.copyLink)),
        if (url != null) PopupMenuItem(value: 'open', height: 34, child: Text(l.openLink)),
        if (!widget.readOnly) PopupMenuItem(value: 'eye', height: 34, child: Text(f.hidden ? l.showValue : l.hideValue)),
      ],
    );
    if (!mounted) return;
    switch (r) {
      case 'copy':
        _copy(f.value);
      case 'copyLink':
        _copy(url.toString());
      case 'open':
        context.app.platform.openUrl(url!);
      case 'eye':
        _toggleHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final l = context.l;
    final url = f.isEmailAddress ? null : f.url;
    final isLink = url != null;
    return Hover(
      builder: (context, hovered) {
        final showActions = hovered || f.hidden;
        final valueStyle = t.value.copyWith(
          decoration: isLink && !f.hidden ? TextDecoration.underline : null,
          decorationColor: hovered ? c.text2 : c.text3,
          decorationThickness: 1,
          letterSpacing: f.hidden ? 1.5 : null,
        );
        final value = f.hidden ? '•' * 12 : f.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(color: hovered ? c.hover : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: widget.keyWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
                child: Text(f.key, style: t.key),
              ),
            ),
            Expanded(
              child: SelectionContainer.disabled(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => isLink && !f.hidden ? context.app.platform.openUrl(url) : _copy(f.value),
                    onSecondaryTapDown: (d) => _menu(d.globalPosition, url),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Tooltip(
                        message: isLink && f.link != null && !f.hidden ? f.link! : '',
                        child: Text(value, style: valueStyle),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 72,
              height: 34,
              child: SelectionContainer.disabled(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: showActions || _copied ? 1 : 0,
                  child: _copied
                      ? Center(child: Text(l.copied, style: t.small.copyWith(color: c.text2)))
                      : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (!widget.readOnly)
                            VIconButton(
                              icon: f.hidden ? Ic.eyeOff : Ic.eye,
                              size: 15,
                              tooltip: f.hidden ? l.showValue : l.hideValue,
                              onPressed: _toggleHidden,
                            ),
                          VIconButton(
                            icon: Ic.copy,
                            size: 15,
                            tooltip: isLink && f.link == null ? l.copyLink : l.copy,
                            onPressed: () => _copy(f.value),
                          ),
                        ]),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
