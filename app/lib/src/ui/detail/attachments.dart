// Attachments: list with open / save a copy, previews for images, add by drag & drop or picker.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/crypto/file_crypto.dart';
import '../../core/model/item.dart';
import '../../core/vault/vault_controller.dart';
import '../app.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

IconData iconForMime(String mime, String name) {
  final ext = p.extension(name).toLowerCase();
  if (mime.startsWith('image/')) return Ic.fileImage;
  if (mime.startsWith('audio/')) return Ic.fileAudio;
  if (mime.startsWith('video/')) return Ic.fileVideo;
  if (mime.contains('zip') || ['.rar', '.7z', '.tar', '.gz'].contains(ext)) return Ic.fileArchive;
  if (mime.contains('sheet') || mime.contains('excel') || ext == '.csv' || ext == '.numbers') return Ic.fileSpreadsheet;
  if (['.pem', '.p12', '.pfx', '.key', '.cer', '.crt', '.asc', '.gpg'].contains(ext)) return Ic.fileKey;
  if (mime.startsWith('text/') || mime.contains('pdf') || mime.contains('word') || ext == '.pages') return Ic.fileText;
  return Ic.file;
}

class AttachmentTile extends StatefulWidget {
  const AttachmentTile({super.key, required this.attachment, required this.vault, this.onRemove});
  final Attachment attachment;
  final VaultController vault;

  /// Edit mode: remove instead of open.
  final VoidCallback? onRemove;

  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  bool _busy = false;
  Future<dynamic>? _preview;

  Attachment get a => widget.attachment;

  @override
  void initState() {
    super.initState();
    if (a.isImage) _preview = widget.vault.attachmentBytes(a);
  }

  Future<void> _open() async {
    final app = context.app;
    final l = context.l;
    setState(() => _busy = true);
    try {
      final f = await widget.vault.exportAttachment(a, app.openDir);
      final ok = await app.platform.openFile(f.path);
      if (!ok && mounted) context.toasts.show(l.cannotOpen);
    } catch (e) {
      if (mounted) context.toasts.show(l.cannotOpen);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCopy() async {
    final app = context.app;
    final l = context.l;
    final dest = await app.platform.saveFileDialog(a.name);
    if (dest == null) return;
    setState(() => _busy = true);
    try {
      if (!await widget.vault.sync.blobs.file(a.id).exists()) await widget.vault.sync.downloadBlob(a.id);
      await FileCrypto.decryptFile(widget.vault.sync.blobs.file(a.id).path, dest, a.key);
      if (mounted) context.toasts.show(l.fileSaved);
    } catch (_) {
      if (mounted) context.toasts.show(l.cannotOpen);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _menu(Offset pos) async {
    final l = context.l;
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'open', height: 34, child: Text(l.open)),
        PopupMenuItem(value: 'save', height: 34, child: Text(l.saveCopy)),
      ],
    );
    if (r == 'open') _open();
    if (r == 'save') _saveCopy();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final l = context.l;
    final editing = widget.onRemove != null;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: widget.vault.sync.transfers,
      builder: (context, transfers, _) {
        final progress = transfers[a.id];
        return Hover(
          cursor: editing ? MouseCursor.defer : SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: editing || _busy ? null : _open,
            onSecondaryTapDown: editing ? null : (d) => _menu(d.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: hovered && !editing ? c.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: editing ? c.inputBorder : Colors.transparent),
              ),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: _preview == null
                      ? Icon(iconForMime(a.mime, a.name), size: 20, color: c.text2)
                      : FutureBuilder(
                          future: _preview,
                          builder: (context, snap) => snap.data == null
                              ? Icon(iconForMime(a.mime, a.name), size: 20, color: c.text2)
                              : ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.memory(snap.data, fit: BoxFit.cover)),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(a.name, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      progress != null ? '${(progress * 100).round()}%' : (_busy ? l.downloading : humanSize(a.size)),
                      style: t.small.copyWith(color: c.text3),
                    ),
                  ]),
                ),
                if (_busy || progress != null)
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, value: progress, color: c.text2)),
                if (editing) VIconButton(icon: Ic.x, size: 14, tooltip: l.removeAttachment, onPressed: widget.onRemove),
                if (!editing && hovered && !_busy)
                  VIconButton(icon: Ic.download, size: 14, tooltip: l.saveCopy, onPressed: _saveCopy),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Maximum size of one attachment (docs/SPEC.md §6.5).
const maxAttachmentBytes = 200 * 1024 * 1024;

/// Encrypts the given files and returns the attachments (skipping files that are too large).
Future<List<Attachment>> addFiles(BuildContext context, VaultController vault, List<File> files) async {
  final out = <Attachment>[];
  final toasts = context.toasts;
  final l = context.l;
  for (final f in files) {
    try {
      if (!await f.exists()) continue;
      if (await f.length() > maxAttachmentBytes) {
        toasts.show(l.fileTooLarge(p.basename(f.path)));
        continue;
      }
      out.add(await vault.addAttachment(f));
    } catch (e) {
      toasts.show(l.genericError('$e'));
    }
  }
  return out;
}
