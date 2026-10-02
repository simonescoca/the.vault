// Creating and editing an entry (docs/SPEC.md §6).
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/model/item_draft.dart';
import '../../core/model/text_utils.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../home/home_controller.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/popover.dart';
import 'attachments.dart';
import 'detail_view.dart';
import 'generator_panel.dart';

class DetailEdit extends StatefulWidget {
  const DetailEdit({super.key, required this.home, required this.onSave, required this.onCancel});
  final HomeController home;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  State<DetailEdit> createState() => DetailEditState();
}

class DetailEditState extends State<DetailEdit> {
  late final ItemDraft d = widget.home.draft!;
  late final _title = TextEditingController(text: d.title);
  late final _desc = TextEditingController(text: d.description);
  final _titleFocus = FocusNode();
  final Map<String, (TextEditingController, TextEditingController, FocusNode, FocusNode)> _rows = {};
  bool _dragging = false;
  int _adding = 0;
  bool titleError = false;

  VaultController get vault => widget.home.vault;

  @override
  void initState() {
    super.initState();
    _title.addListener(() {
      d.title = _title.text;
      if (titleError && _title.text.trim().isNotEmpty) setState(() => titleError = false);
      _changed();
    });
    _desc.addListener(() {
      d.description = _desc.text;
      _changed();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (d.isNew) _titleFocus.requestFocus();
    });
  }

  void _changed() => widget.home.markDirty();

  (TextEditingController, TextEditingController, FocusNode, FocusNode) _ctrl(FieldDraft f) {
    return _rows.putIfAbsent(f.id, () {
      final k = TextEditingController(text: f.key)
        ..addListener(() {
          f.key = _rows[f.id]!.$1.text;
          _changed();
        });
      final v = TextEditingController(text: f.value)
        ..addListener(() {
          final before = d.titleSuggestion;
          f.value = _rows[f.id]!.$2.text;
          _changed();
          if (before != d.titleSuggestion) setState(() {});
        });
      return (k, v, FocusNode(), FocusNode());
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _titleFocus.dispose();
    for (final r in _rows.values) {
      r.$1.dispose();
      r.$2.dispose();
      r.$3.dispose();
      r.$4.dispose();
    }
    super.dispose();
  }

  /// Puts the cursor in the title and shows the error (save refused because of an empty title).
  void needsTitle() {
    setState(() => titleError = true);
    _titleFocus.requestFocus();
  }

  void _addRow({int? at, bool focus = true}) {
    final f = d.addRow(at: at);
    _changed();
    setState(() {});
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl(f).$3.requestFocus());
    }
  }

  void _removeRow(FieldDraft f) {
    if (d.removeRow(f.id)) {
      final r = _rows.remove(f.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        r?.$1.dispose();
        r?.$2.dispose();
        r?.$3.dispose();
        r?.$4.dispose();
      });
      _changed();
      setState(() {});
    }
  }

  Future<void> _addFiles(List<File> files) async {
    setState(() => _adding += files.length);
    final added = await addFiles(context, vault, files);
    if (!mounted) return;
    setState(() {
      _adding -= files.length;
      d.files.addAll(added);
    });
    if (added.isNotEmpty) _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final keyW = keyColumnWidth(context, d.fields.map((f) => f.key.isEmpty ? (f.suggestion ?? l.keyHint) : f.key)).clamp(130.0, 180.0);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _addFiles([for (final x in detail.files) File(x.path)]);
      },
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DetailHeader(children: [
            VButton(label: l.cancel, kind: VButtonKind.secondary, onPressed: widget.onCancel),
            const SizedBox(width: 8),
            VButton(label: l.save, icon: Ic.check, onPressed: _adding > 0 ? null : widget.onSave),
          ]),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(40, 6, 40, 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _title,
                  focusNode: _titleFocus,
                  style: t.title,
                  cursorWidth: 1.6,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: d.titleSuggestion ?? l.titleHint,
                    hintStyle: t.title.copyWith(color: c.text3),
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  child: titleError
                      ? Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.needsTitle, style: t.small.copyWith(color: c.danger)))
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 18),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: d.fields.length,
                  proxyDecorator: (child, i, anim) => Material(
                    color: c.bg,
                    elevation: 6,
                    shadowColor: c.shadow,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  ),
                  onReorderItem: (from, to) {
                    setState(() => d.moveRowTo(from, to));
                    _changed();
                  },
                  itemBuilder: (context, i) {
                    final f = d.fields[i];
                    return _EditRow(
                      key: ValueKey(f.id),
                      index: i,
                      field: f,
                      ctrl: _ctrl(f),
                      keyWidth: keyW,
                      canRemove: d.canRemoveRow,
                      isLast: i == d.fields.length - 1,
                      onRemove: () => _removeRow(f),
                      onChanged: () {
                        _changed();
                        setState(() {});
                      },
                      onEnterInLast: () => _addRow(),
                      onEnterNext: () => _ctrl(d.fields[i + 1]).$3.requestFocus(),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: VButton(label: l.addRow, kind: VButtonKind.text, icon: Ic.plus, onPressed: () => _addRow()),
                ),
                const SizedBox(height: 18),
                VTextField(controller: _desc, hint: l.descriptionHint, maxLines: null, minLines: 3, style: t.description),
                const SizedBox(height: 22),
                Text(l.attachments, style: t.small.copyWith(color: c.text3)),
                const SizedBox(height: 8),
                for (final a in d.files)
                  AttachmentTile(
                    key: ValueKey(a.id),
                    attachment: a,
                    vault: vault,
                    onRemove: () {
                      setState(() => d.files.remove(a));
                      _changed();
                    },
                  ),
                if (_adding > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.text2)),
                      const SizedBox(width: 10),
                      Text(l.uploading, style: t.small),
                    ]),
                  ),
                _DropZone(onChoose: () async {
                  final files = await context.app.platform.pickFiles();
                  if (files.isNotEmpty) await _addFiles(files);
                }),
              ]),
            ),
          ),
        ]),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.primary.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Center(child: Icon(Ic.paperclip, size: 32, color: c.text2)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onChoose});
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.inputBorder),
        color: c.inputBg,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Ic.paperclip, size: 15, color: c.text3),
        const SizedBox(width: 8),
        Text(l.dropFiles, style: t.small),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onChoose,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(l.chooseFiles, style: t.small.copyWith(color: c.text, decoration: TextDecoration.underline, decorationColor: c.text3)),
          ),
        ),
      ]),
    );
  }
}

class _EditRow extends StatefulWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.field,
    required this.ctrl,
    required this.keyWidth,
    required this.canRemove,
    required this.isLast,
    required this.onRemove,
    required this.onChanged,
    required this.onEnterInLast,
    required this.onEnterNext,
  });

  final int index;
  final FieldDraft field;
  final (TextEditingController, TextEditingController, FocusNode, FocusNode) ctrl;
  final double keyWidth;
  final bool canRemove;
  final bool isLast;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final VoidCallback onEnterInLast;
  final VoidCallback onEnterNext;

  @override
  State<_EditRow> createState() => _EditRowState();
}

class _EditRowState extends State<_EditRow> {
  FieldDraft get f => widget.field;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.text;
    final c = context.colors;
    final (keyCtrl, valueCtrl, keyFocus, valueFocus) = widget.ctrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: l.dragRow,
                child: SizedBox(width: 22, height: 36, child: Icon(Ic.gripVertical, size: 15, color: c.text3)),
              ),
            ),
          ),
          SizedBox(
            width: widget.keyWidth,
            child: VTextField(
              controller: keyCtrl,
              focusNode: keyFocus,
              hint: f.suggestion ?? l.keyHint,
              dense: true,
              style: t.key.copyWith(color: c.text),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              // Only listens to Enter in the value field: Tab must not stop here.
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                  widget.isLast ? widget.onEnterInLast() : widget.onEnterNext();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: VTextField(
                controller: valueCtrl,
                focusNode: valueFocus,
                hint: l.valueHint,
                mono: true,
                dense: true,
                maxLines: null,
                obscure: false,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ),
          const SizedBox(width: 4),
          VIconButton(
            icon: f.hidden ? Ic.eyeOff : Ic.eye,
            size: 15,
            box: 30,
            active: f.hidden,
            tooltip: f.hidden ? l.showValue : l.hideValue,
            onPressed: () {
              setState(() => f.hidden = !f.hidden);
              widget.onChanged();
            },
          ),
          PopoverButton(
            icon: Ic.link,
            active: f.link != null,
            tooltip: f.link == null ? l.addLink : l.editLink,
            builder: (ctx, close) => _LinkPanel(
              initial: f.link ?? '',
              onSave: (v) {
                setState(() => f.link = v);
                widget.onChanged();
                close();
              },
            ),
          ),
          PopoverButton(
            icon: Ic.wandSparkles,
            tooltip: l.generatePassword,
            builder: (ctx, close) => GeneratorPanel(
              onUse: (v) {
                valueCtrl.text = v;
                if (f.key.isEmpty && f.suggestion == null) keyCtrl.text = l.suggestionPassword;
              },
              onClose: close,
            ),
          ),
          VIconButton(icon: Ic.minus, size: 15, box: 30, tooltip: l.removeRow, onPressed: widget.canRemove ? widget.onRemove : null),
        ]),
        if (f.link != null && f.link!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 22 + widget.keyWidth + 8, top: 4),
            child: Row(children: [
              Icon(Ic.link, size: 12, color: c.text3),
              const SizedBox(width: 6),
              Flexible(child: Text(normalizeLink(f.link!) ?? f.link!, style: t.small, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ]),
    );
  }
}

class _LinkPanel extends StatefulWidget {
  const _LinkPanel({required this.initial, required this.onSave});
  final String initial;
  final ValueChanged<String?> onSave;

  @override
  State<_LinkPanel> createState() => _LinkPanelState();
}

class _LinkPanelState extends State<_LinkPanel> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  void _ok() {
    final v = _c.text.trim();
    if (v.isEmpty) {
      widget.onSave(null);
      return;
    }
    final n = normalizeLink(v);
    if (n == null) {
      setState(() => _error = context.l.linkInvalid);
      return;
    }
    widget.onSave(n);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.addLink, style: context.text.section),
      const SizedBox(height: 10),
      VTextField(controller: _c, hint: l.linkHint, mono: true, autofocus: true, error: _error, onSubmitted: (_) => _ok(), keyboardType: TextInputType.url),
      const SizedBox(height: 12),
      Row(children: [
        if (widget.initial.isNotEmpty) VButton(label: l.removeLink, kind: VButtonKind.text, onPressed: () => widget.onSave(null)),
        const Spacer(),
        VButton(label: l.done, onPressed: _ok),
      ]),
    ]);
  }
}
