// Local database of a device (SQLite). It keeps the records exactly as the server does — encrypted —
// plus the local changes waiting to be sent, so the app works offline.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';

/// A record as last received from the server.
class RecordRow {
  RecordRow({required this.id, required this.rev, required this.data, required this.deleted, required this.blobs});
  final String id;
  final int rev;
  final Uint8List? data;
  final bool deleted;
  final List<String> blobs;
}

/// A local change not yet acknowledged by the server.
class PendingRow {
  PendingRow({
    required this.id,
    required this.baseRev,
    required this.op,
    required this.data,
    required this.blobs,
    required this.version,
  });
  final String id;

  /// Server revision this change is based on (0 = the record does not exist on the server).
  final int baseRev;

  /// 'put' or 'delete'.
  final String op;
  final Uint8List? data;
  final List<String> blobs;

  /// Incremented at every local write: lets the sync engine know whether the row changed while it was being sent.
  final int version;

  bool get isDelete => op == 'delete';
}

/// State of an encrypted attachment file on this device.
class BlobRow {
  BlobRow({required this.id, required this.state, required this.size});
  final String id;

  /// `local`: file here, not yet on the server · `synced`: here and on the server ·
  /// `remote`: only on the server (to download).
  final String state;
  final int size;
}

class LocalDb {
  LocalDb._(this._db) {
    _migrate();
  }

  final Database _db;

  factory LocalDb.open(String path) => LocalDb._(sqlite3.open(path));
  factory LocalDb.memory() => LocalDb._(sqlite3.openInMemory());

  void close() => _db.close();

  void _migrate() {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    final v = _db.select('PRAGMA user_version').first.values.first as int;
    if (v < 1) {
      _db.execute('''
        CREATE TABLE records (
          id TEXT PRIMARY KEY, rev INTEGER NOT NULL, data BLOB, deleted INTEGER NOT NULL DEFAULT 0, blobs TEXT NOT NULL DEFAULT '[]'
        );
        CREATE TABLE pending (
          id TEXT PRIMARY KEY, base_rev INTEGER NOT NULL, op TEXT NOT NULL, data BLOB, blobs TEXT NOT NULL DEFAULT '[]',
          version INTEGER NOT NULL DEFAULT 1, seq INTEGER NOT NULL
        );
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE blobs (id TEXT PRIMARY KEY, state TEXT NOT NULL, size INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE favicons (domain TEXT PRIMARY KEY, data BLOB, fetched_at INTEGER NOT NULL);
        PRAGMA user_version = 1;
      ''');
    }
    if (v < 2) {
      // Site icons: stored under a keyed hash and encrypted (version 1 kept the site names in clear).
      _db.execute('''
        DROP TABLE IF EXISTS favicons;
        CREATE TABLE favicons (name TEXT PRIMARY KEY, data BLOB, fetched_at INTEGER NOT NULL);
        PRAGMA user_version = 2;
      ''');
    }
  }

  T transaction<T>(T Function() fn) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final r = fn();
      _db.execute('COMMIT');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static List<String> _blobs(Object? v) => [for (final b in jsonDecode((v as String?) ?? '[]') as List) b as String];

  // ------------------------------------------------------------------ records

  void upsertRecord(RecordRow r) {
    _db.execute(
      'INSERT INTO records(id, rev, data, deleted, blobs) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET rev = excluded.rev, data = excluded.data, deleted = excluded.deleted, blobs = excluded.blobs',
      [r.id, r.rev, r.data, r.deleted ? 1 : 0, jsonEncode(r.blobs)],
    );
  }

  RecordRow? record(String id) {
    final rows = _db.select('SELECT id, rev, data, deleted, blobs FROM records WHERE id = ?', [id]);
    return rows.isEmpty ? null : _recordRow(rows.first);
  }

  RecordRow _recordRow(Row r) => RecordRow(
        id: r['id'] as String,
        rev: r['rev'] as int,
        data: r['data'] as Uint8List?,
        deleted: (r['deleted'] as int) == 1,
        blobs: _blobs(r['blobs']),
      );

  List<RecordRow> allRecords() =>
      [for (final r in _db.select('SELECT id, rev, data, deleted, blobs FROM records')) _recordRow(r)];

  // ------------------------------------------------------------------ pending

  /// Queues a local write. If the record already has a pending change, its base revision is kept
  /// (it is still the last version known from the server) and the content is replaced.
  void putPending({required String id, required String op, Uint8List? data, List<String> blobs = const []}) {
    transaction(() {
      final existing = _db.select('SELECT base_rev, version FROM pending WHERE id = ?', [id]);
      if (existing.isNotEmpty) {
        _db.execute('UPDATE pending SET op = ?, data = ?, blobs = ?, version = version + 1 WHERE id = ?',
            [op, data, jsonEncode(blobs), id]);
      } else {
        final base = record(id)?.rev ?? 0;
        final seq = (_db.select('SELECT coalesce(max(seq), 0) + 1 AS s FROM pending').first['s'] as int);
        _db.execute('INSERT INTO pending(id, base_rev, op, data, blobs, version, seq) VALUES (?, ?, ?, ?, ?, 1, ?)',
            [id, base, op, data, jsonEncode(blobs), seq]);
      }
    });
  }

  PendingRow? pending(String id) {
    final rows = _db.select('SELECT * FROM pending WHERE id = ?', [id]);
    return rows.isEmpty ? null : _pendingRow(rows.first);
  }

  PendingRow _pendingRow(Row r) => PendingRow(
        id: r['id'] as String,
        baseRev: r['base_rev'] as int,
        op: r['op'] as String,
        data: r['data'] as Uint8List?,
        blobs: _blobs(r['blobs']),
        version: r['version'] as int,
      );

  List<PendingRow> pendingQueue() => [for (final r in _db.select('SELECT * FROM pending ORDER BY seq')) _pendingRow(r)];

  int get pendingCount => _db.select('SELECT count(*) AS n FROM pending').first['n'] as int;

  /// The server accepted [sent] with [newRev]: store it as server state and drop the pending change,
  /// unless the user changed the record again in the meantime (then it stays queued on top of [newRev]).
  void acknowledge(PendingRow sent, int newRev) {
    transaction(() {
      upsertRecord(RecordRow(
        id: sent.id,
        rev: newRev,
        data: sent.isDelete ? null : sent.data,
        deleted: sent.isDelete,
        blobs: sent.isDelete ? const [] : sent.blobs,
      ));
      final cur = pending(sent.id);
      if (cur != null && cur.version == sent.version) {
        _db.execute('DELETE FROM pending WHERE id = ?', [sent.id]);
      } else if (cur != null) {
        _db.execute('UPDATE pending SET base_rev = ? WHERE id = ?', [newRev, sent.id]);
      }
    });
  }

  void dropPending(String id) => _db.execute('DELETE FROM pending WHERE id = ?', [id]);

  /// Rebases a pending change on a newer server revision (used after "overwrite" in a conflict).
  void rebasePending(String id, int baseRev) => _db.execute('UPDATE pending SET base_rev = ? WHERE id = ?', [baseRev, id]);

  // ------------------------------------------------------------ effective view

  /// What the user sees: server records with the local changes applied on top.
  /// Returns id → (data, blobs) for live records only.
  Map<String, ({Uint8List data, List<String> blobs, bool local})> effective() {
    final out = <String, ({Uint8List data, List<String> blobs, bool local})>{};
    for (final r in allRecords()) {
      if (!r.deleted && r.data != null) out[r.id] = (data: r.data!, blobs: r.blobs, local: false);
    }
    for (final p in pendingQueue()) {
      if (p.isDelete) {
        out.remove(p.id);
      } else if (p.data != null) {
        out[p.id] = (data: p.data!, blobs: p.blobs, local: true);
      }
    }
    return out;
  }

  /// Blob ids referenced by any live record or pending change.
  Set<String> referencedBlobs() {
    final s = <String>{};
    for (final v in effective().values) {
      s.addAll(v.blobs);
    }
    return s;
  }

  // ---------------------------------------------------------------------- meta

  String? meta(String key) {
    final r = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setMeta(String key, String? value) {
    if (value == null) {
      _db.execute('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      _db.execute('INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', [key, value]);
    }
  }

  int get cursor => int.tryParse(meta('cursor') ?? '') ?? 0;
  set cursor(int v) => setMeta('cursor', '$v');

  // --------------------------------------------------------------------- blobs

  void setBlob(String id, String state, int size) => _db.execute(
        'INSERT INTO blobs(id, state, size) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET state = excluded.state, size = excluded.size',
        [id, state, size],
      );

  BlobRow? blob(String id) {
    final r = _db.select('SELECT id, state, size FROM blobs WHERE id = ?', [id]);
    return r.isEmpty ? null : BlobRow(id: r.first['id'] as String, state: r.first['state'] as String, size: r.first['size'] as int);
  }

  List<BlobRow> blobsInState(String state) => [
        for (final r in _db.select('SELECT id, state, size FROM blobs WHERE state = ?', [state]))
          BlobRow(id: r['id'] as String, state: r['state'] as String, size: r['size'] as int)
      ];

  List<BlobRow> allBlobs() => [
        for (final r in _db.select('SELECT id, state, size FROM blobs'))
          BlobRow(id: r['id'] as String, state: r['state'] as String, size: r['size'] as int)
      ];

  void deleteBlob(String id) => _db.execute('DELETE FROM blobs WHERE id = ?', [id]);

  // ------------------------------------------------------------------ favicons

  /// A cached site icon; [name] and [data] are opaque (hashed and encrypted by the favicon service).
  ({Uint8List? data, int fetchedAt})? favicon(String name) {
    final r = _db.select('SELECT data, fetched_at FROM favicons WHERE name = ?', [name]);
    if (r.isEmpty) return null;
    return (data: r.first['data'] as Uint8List?, fetchedAt: r.first['fetched_at'] as int);
  }

  void setFavicon(String name, Uint8List? data, int fetchedAt) => _db.execute(
        'INSERT INTO favicons(name, data, fetched_at) VALUES (?, ?, ?) '
        'ON CONFLICT(name) DO UPDATE SET data = excluded.data, fetched_at = excluded.fetched_at',
        [name, data, fetchedAt],
      );

  /// The stored icon names (tests check that they reveal nothing).
  @visibleForTesting
  List<String> debugFaviconNames() => [for (final r in _db.select('SELECT name FROM favicons')) r['name'] as String];

  /// Removes everything (sign out / revoked device).
  void wipe() {
    transaction(() {
      for (final t in ['records', 'pending', 'meta', 'blobs', 'favicons']) {
        _db.execute('DELETE FROM $t');
      }
    });
  }
}
