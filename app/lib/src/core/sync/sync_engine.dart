// Sync engine: sends local changes, receives the others' and moves encrypted attachments (docs/PROTOCOL.md §4).
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/api_client.dart';
import '../storage/local_db.dart';

enum SyncState { idle, syncing, offline, error }

/// Called when the server refused a local change because the record changed meanwhile.
/// [base] is the server version the local change started from (if this device had it).
/// The handler updates the pending queue (drop, rebase, or re-create as a copy) and returns true,
/// or returns false to retry later (e.g. the vault is locked and cannot decrypt).
typedef ConflictHandler = Future<bool> Function(PendingRow local, RecordRow? base, RecordRow current);

/// Encrypted attachment files of this device.
class BlobFiles {
  BlobFiles(this.dir);
  final String dir;

  File file(String id) => File(p.join(dir, '$id.enc'));
  File partial(String id) => File(p.join(dir, '$id.part'));

  Future<void> ensure() => Directory(dir).create(recursive: true);
}

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.blobs,
    required this.onConflict,
    this.onChanged,
    this.onUnauthorized,
  });

  final LocalDb db;
  final ApiClient api;
  final BlobFiles blobs;
  ConflictHandler onConflict;

  /// Record ids that changed locally because of a sync.
  void Function(Set<String> ids)? onChanged;

  /// The server does not recognize this device any more (revoked or signed out elsewhere).
  Future<void> Function()? onUnauthorized;

  final state = ValueNotifier<SyncState>(SyncState.idle);

  /// Blob ids being uploaded/downloaded right now → progress 0..1.
  final transfers = ValueNotifier<Map<String, double>>({});

  Object? lastError;
  Completer<void>? _inflight;
  bool _again = false;
  bool _disposed = false;

  /// Requests a sync. Calls while a sync is running are merged into one more round.
  Future<void> sync() {
    if (_disposed) return Future.value();
    final current = _inflight;
    if (current != null) {
      _again = true;
      return current.future;
    }
    final c = _inflight = Completer<void>();
    () async {
      try {
        do {
          _again = false;
          await _runOnce();
        } while (_again && !_disposed);
      } finally {
        _inflight = null;
        c.complete();
      }
    }();
    return c.future;
  }

  Future<void> _runOnce() async {
    state.value = SyncState.syncing;
    final changed = <String>{};
    try {
      await blobs.ensure();
      await _push(changed);
      await _pull(changed);
      if (changed.isNotEmpty) onChanged?.call(changed);
      state.value = SyncState.idle;
      lastError = null;
      _transferFuture = _transferBlobs();
    } on NetworkException catch (e) {
      if (changed.isNotEmpty) onChanged?.call(changed);
      lastError = e;
      state.value = SyncState.offline;
    } on ApiException catch (e) {
      if (changed.isNotEmpty) onChanged?.call(changed);
      lastError = e;
      if (e.status == 401) {
        state.value = SyncState.error;
        await onUnauthorized?.call();
        return;
      }
      state.value = SyncState.error;
      debugPrint('sync error: $e');
    }
  }

  // ------------------------------------------------------------------ push

  Future<void> _push(Set<String> changed) async {
    final deferred = <String>{};
    for (var round = 0; round < 50; round++) {
      final queue = db.pendingQueue().where((p) => !deferred.contains(p.id)).toList();
      if (queue.isEmpty) return;
      var progressed = false;
      for (final item in queue) {
        final pending = db.pending(item.id);
        if (pending == null) continue;
        try {
          if (pending.isDelete && pending.baseRev == 0) {
            db.dropPending(pending.id); // never reached the server
            progressed = true;
            continue;
          }
          if (!pending.isDelete) await _ensureUploaded(pending.blobs);
          final rev = pending.isDelete
              ? await api.deleteRecord(pending.id, pending.baseRev)
              : await api.putRecord(pending.id, pending.baseRev, pending.data!, pending.blobs);
          db.acknowledge(pending, rev);
          changed.add(pending.id);
          progressed = true;
        } on ConflictException catch (e) {
          final base = db.record(pending.id);
          db.upsertRecord(e.current);
          changed.add(pending.id);
          final resolved = await onConflict(pending, base, e.current);
          if (resolved) {
            progressed = true;
          } else {
            deferred.add(pending.id);
          }
        } on ApiException catch (e) {
          if (e.status == 404 && pending.isDelete) {
            db.dropPending(pending.id);
            progressed = true;
          } else if (e.code == 'missing_blob') {
            // The server collected an attachment we thought was uploaded: send it again if we still have it.
            final missing = [for (final b in (e.body['blobs'] as List? ?? const [])) b as String];
            var fixed = false;
            for (final b in missing) {
              if (await blobs.file(b).exists()) {
                db.setBlob(b, 'local', await blobs.file(b).length());
                fixed = true;
              }
            }
            if (!fixed) rethrow;
            progressed = true;
          } else {
            rethrow;
          }
        }
      }
      if (!progressed) return;
    }
  }

  Future<void> _ensureUploaded(List<String> ids) async {
    for (final id in ids) {
      final row = db.blob(id);
      if (row == null || row.state != 'local') continue;
      await _upload(id);
    }
  }

  Future<void> _upload(String id) async {
    final f = blobs.file(id);
    final size = await f.length();
    final start = await api.startBlob(id, size);
    if (!start.complete) {
      final parts = (size + start.partSize - 1) ~/ start.partSize;
      final raf = await f.open();
      try {
        for (var n = 0; n < parts; n++) {
          if (start.received.contains(n)) continue;
          await raf.setPosition(n * start.partSize);
          final len = (n == parts - 1) ? size - n * start.partSize : start.partSize;
          final bytes = await raf.read(len);
          await api.putBlobPart(id, n, bytes);
          _progress(id, (n + 1) / parts);
        }
      } finally {
        await raf.close();
      }
      final digest = await hash.sha256.bind(f.openRead()).first;
      await api.completeBlob(id, parts, digest.toString());
    }
    db.setBlob(id, 'synced', size);
    _progress(id, null);
  }

  void _progress(String id, double? v) {
    if (_disposed) return;
    final m = Map<String, double>.from(transfers.value);
    if (v == null) {
      m.remove(id);
    } else {
      m[id] = v;
    }
    transfers.value = m;
  }

  // ------------------------------------------------------------------ pull

  Future<void> _pull(Set<String> changed) async {
    var since = db.cursor;
    while (true) {
      final page = await api.records(since);
      db.transaction(() {
        for (final r in page.records) {
          db.upsertRecord(r);
          for (final b in r.blobs) {
            if (db.blob(b) == null) db.setBlob(b, 'remote', 0);
          }
        }
        db.cursor = page.more ? page.records.last.rev : page.latest;
      });
      changed.addAll(page.records.map((r) => r.id));
      if (!page.more || page.records.isEmpty) return;
      since = page.records.last.rev;
    }
  }

  // ----------------------------------------------------------------- blobs

  bool _transferring = false;
  Future<void>? _transferFuture;
  final Map<String, Future<void>> _downloads = {};

  /// Downloads the attachments this device does not have yet and removes the unused ones.
  Future<void> _transferBlobs() async {
    if (_transferring || _disposed) return;
    _transferring = true;
    try {
      final referenced = db.referencedBlobs();
      for (final b in db.blobsInState('remote')) {
        if (_disposed) return;
        if (!referenced.contains(b.id)) continue;
        try {
          await downloadBlob(b.id);
        } catch (e) {
          debugPrint('download of ${b.id} failed: $e');
        }
      }
      if (!_disposed) await _cleanup(referenced);
    } catch (e) {
      if (!_disposed) debugPrint('attachment maintenance failed: $e');
    } finally {
      _transferring = false;
    }
  }

  /// Downloads one attachment now (e.g. the user opens it before the background download).
  /// Concurrent calls for the same attachment share one download.
  Future<void> downloadBlob(String id) {
    final running = _downloads[id];
    if (running != null) return running;
    // The block body matters: `() => _downloads.remove(id)` would return the removed future
    // itself, and whenComplete would then wait for its own result forever.
    final f = _download(id).whenComplete(() {
      _downloads.remove(id);
    });
    _downloads[id] = f;
    return f;
  }

  Future<void> _download(String id) async {
    final row = db.blob(id);
    if (row != null && row.state != 'remote' && await blobs.file(id).exists()) return;
    final part = blobs.partial(id);
    final from = await part.exists() ? await part.length() : 0;
    final sink = part.openWrite(mode: FileMode.append);
    String? etag;
    try {
      _progress(id, 0);
      etag = await api.downloadBlob(id, sink, from: from);
      await sink.close();
    } catch (e) {
      await sink.close();
      if (e is ApiException && e.code == 'range_ignored') await part.delete();
      _progress(id, null);
      rethrow;
    }
    if (etag != null && etag.length == 64) {
      final digest = await hash.sha256.bind(part.openRead()).first;
      if (digest.toString() != etag) {
        await part.delete();
        _progress(id, null);
        throw ApiException(0, 'checksum_mismatch', 'downloaded attachment is corrupted');
      }
    }
    final size = await part.length();
    await part.rename(blobs.file(id).path);
    db.setBlob(id, 'synced', size);
    _progress(id, null);
  }

  Future<void> _cleanup(Set<String> referenced) async {
    final dayAgo = DateTime.now().subtract(const Duration(hours: 24));
    for (final b in db.allBlobs()) {
      if (referenced.contains(b.id) || protectedBlobs.contains(b.id)) continue;
      final f = blobs.file(b.id);
      if (b.state == 'local') {
        // Added while editing and never saved: keep it for a day in case the edit is still open.
        if (await f.exists() && (await f.lastModified()).isAfter(dayAgo)) continue;
      }
      if (await f.exists()) await f.delete();
      final part = blobs.partial(b.id);
      if (await part.exists()) await part.delete();
      db.deleteBlob(b.id);
    }
  }

  /// Attachments of entries being edited right now (not referenced by any record yet).
  final Set<String> protectedBlobs = {};

  /// Stores a freshly encrypted attachment file as "to upload".
  Future<void> addLocalBlob(String id, int size) async {
    db.setBlob(id, 'local', size);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _inflight?.future;
    await _transferFuture?.timeout(const Duration(seconds: 5), onTimeout: () {});
    state.dispose();
    transfers.dispose();
  }

  @visibleForTesting
  Future<void> waitTransfers() async {
    while (_transferring) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _transferBlobs();
  }
}

/// Reads a whole encrypted blob file (small files, previews).
Future<Uint8List> readBlobFile(BlobFiles b, String id) => b.file(id).readAsBytes();
