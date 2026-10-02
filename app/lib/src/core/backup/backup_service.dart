// "Export to file" / "Import" (docs/SECURITY.md §11).
//
// File layout:
//   "THEVAULT-BACKUP\n" ‖ header JSON line {"v":1,"kdf":"argon2id13","ops","mem","salt"} ‖ "\n"
//   ‖ secretstream(XChaCha20-Poly1305, key = Argon2id(password)) of frames:
//       [type 1 byte][length 8 bytes big-endian][data]
//       1 = manifest JSON, 2 = item JSON, 3 = attachment header JSON {"id","size"}, 4 = attachment bytes
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import '../crypto/file_crypto.dart';
import '../crypto/vault_crypto.dart';
import '../model/item.dart';
import '../vault/vault_controller.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

class BackupSummary {
  BackupSummary(this.items, this.files, this.created);
  final int items;
  final int files;
  final DateTime created;
}

class BackupService {
  BackupService(this.crypto);
  final VaultCrypto crypto;

  static const magic = 'THEVAULT-BACKUP\n';
  static const _chunk = 64 * 1024;

  // ------------------------------------------------------------------ export

  /// Writes every entry (trash included) and every attachment to [path].
  Future<BackupSummary> export(VaultController vault, String path, String password, {String appVersion = ''}) async {
    final s = crypto.sodium;
    final salt = crypto.randomBytes(s.crypto.pwhash.saltBytes);
    final ops = s.crypto.pwhash.opsLimitModerate;
    final mem = s.crypto.pwhash.memLimitModerate;
    final key = SecureKey.fromList(s, await VaultCrypto.backupKey(password, salt, ops, mem));
    final items = [...vault.list(Section.all), ...vault.list(Section.trash)];
    final files = <Attachment>[for (final i in items) ...i.files];
    final created = DateTime.now();

    // Make sure every attachment is on this device.
    for (final a in files) {
      if (!await vault.sync.blobs.file(a.id).exists()) await vault.sync.downloadBlob(a.id);
    }

    Stream<List<int>> frames() async* {
      yield _frame(1, utf8.encode(jsonEncode({'created': created.millisecondsSinceEpoch, 'items': items.length, 'files': files.length, 'app': appVersion})));
      for (final i in items) {
        yield _frame(2, utf8.encode(jsonEncode({...i.toJson(), 'id': i.id})));
      }
      for (final a in files) {
        yield _frame(3, utf8.encode(jsonEncode({'id': a.id, 'size': a.size})));
        yield _frameHeader(4, a.size);
        final fk = SecureKey.fromList(s, a.key);
        try {
          yield* s.crypto.secretStream.pullChunked(
            cipherStream: vault.sync.blobs.file(a.id).openRead(),
            key: fk,
            chunkSize: FileCrypto.chunkSize,
          );
        } finally {
          fk.dispose();
        }
      }
    }

    final tmp = File('$path.tmp');
    final sink = tmp.openWrite();
    try {
      sink.add(utf8.encode(magic));
      sink.add(utf8.encode('${jsonEncode({'v': 1, 'kdf': 'argon2id13', 'ops': ops, 'mem': mem, 'salt': base64.encode(salt)})}\n'));
      await sink.addStream(s.crypto.secretStream.pushChunked(messageStream: frames(), key: key, chunkSize: _chunk));
      await sink.close();
      if (await File(path).exists()) await File(path).delete();
      await tmp.rename(path);
    } catch (e) {
      await sink.close().catchError((_) {});
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    } finally {
      key.dispose();
    }
    return BackupSummary(items.length, files.length, created);
  }

  static Uint8List _frameHeader(int type, int length) {
    final b = ByteData(9)
      ..setUint8(0, type)
      ..setUint64(1, length, Endian.big);
    return b.buffer.asUint8List();
  }

  static Uint8List _frame(int type, List<int> data) => Uint8List.fromList([..._frameHeader(type, data.length), ...data]);

  // ------------------------------------------------------------------ import

  Future<({Map<String, dynamic> header, int offset})> _readHeader(String path) async {
    final raf = await File(path).open();
    try {
      final head = await raf.read(4096);
      final m = utf8.encode(magic);
      if (head.length < m.length || utf8.decode(head.sublist(0, m.length), allowMalformed: true) != magic) {
        throw BackupException('not a The Vault backup');
      }
      final nl = head.indexOf(10, m.length);
      if (nl < 0) throw BackupException('damaged header');
      final header = jsonDecode(utf8.decode(head.sublist(m.length, nl))) as Map<String, dynamic>;
      if (header['v'] != 1) throw BackupException('unsupported backup version');
      return (header: header, offset: nl + 1);
    } finally {
      await raf.close();
    }
  }

  Future<SecureKey> _key(Map<String, dynamic> h, String password) async {
    final ops = (h['ops'] as num).toInt();
    final mem = (h['mem'] as num).toInt();
    // The file says how hard the password is to compute: absurd values would freeze or crash the app.
    if (ops < 1 || ops > 10 || mem < 8 << 20 || mem > 1 << 30) throw BackupException('damaged header');
    final bytes = await VaultCrypto.backupKey(password, base64.decode(h['salt'] as String), ops, mem);
    return SecureKey.fromList(crypto.sodium, bytes);
  }

  /// Opens the backup and reads its manifest. Throws [BackupException] on wrong password or damaged file.
  Future<BackupSummary> inspect(String path, String password) async {
    BackupSummary? out;
    await _frames(path, password, (type, data, _) async {
      if (type == 1) {
        final m = jsonDecode(utf8.decode(data!)) as Map<String, dynamic>;
        out = BackupSummary((m['items'] as num).toInt(), (m['files'] as num).toInt(), DateTime.fromMillisecondsSinceEpoch((m['created'] as num).toInt()));
        return false;
      }
      return true;
    });
    if (out == null) throw BackupException('empty backup');
    return out!;
  }

  /// Imports [path] into [vault]. Entries already present keep the most recently modified version.
  /// Returns the number of entries written.
  Future<int> import(VaultController vault, String path, String password, String tempDir) async {
    final incoming = <Item>[];
    final wanted = <String>{};
    final tmp = Directory(p.join(tempDir, 'import-${DateTime.now().microsecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    final extracted = <String, File>{};
    String? currentFile;
    // What the manifest promises, and what was read: a cut file must not import halfway.
    int? expectedItems, expectedFiles;
    var readItems = 0, readFiles = 0;
    try {
      await _frames(path, password, (type, data, stream) async {
        switch (type) {
          case 1:
            final m = jsonDecode(utf8.decode(data!)) as Map<String, dynamic>;
            expectedItems = (m['items'] as num).toInt();
            expectedFiles = (m['files'] as num).toInt();
          case 2:
            readItems++;
            final j = jsonDecode(utf8.decode(data!)) as Map<String, dynamic>;
            final item = Item.fromJson(j['id'] as String, Map<String, dynamic>.from(j)..remove('id'));
            final existing = vault.byId(item.id);
            if (existing == null || item.updated.isAfter(existing.updated)) {
              incoming.add(item);
              wanted.addAll(item.files.map((f) => f.id));
            }
          case 3:
            readFiles++;
            currentFile = (jsonDecode(utf8.decode(data!)) as Map<String, dynamic>)['id'] as String;
          case 4:
            final id = currentFile;
            if (id != null && wanted.contains(id)) {
              final f = File(p.join(tmp.path, id));
              final sink = f.openWrite();
              await sink.addStream(stream!);
              await sink.close();
              extracted[id] = f;
            } else {
              await stream!.drain<void>();
            }
        }
        return true;
      });
      if (readItems != expectedItems || readFiles != expectedFiles) throw BackupException('truncated file');
      var written = 0;
      for (final item in incoming) {
        final files = <Attachment>[];
        for (final a in item.files) {
          final f = extracted[a.id];
          if (f == null) continue; // attachment missing from the backup
          final named = await f.rename(p.join(tmp.path, '${a.id}-${a.name.replaceAll(RegExp(r'[\\/]'), '_')}'));
          final added = await vault.addAttachment(named, mime: a.mime);
          files.add(Attachment(id: added.id, name: a.name, size: added.size, mime: a.mime, key: added.key, added: a.added));
        }
        vault.save(item.copyWith(files: files));
        written++;
      }
      return written;
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  /// Decrypts the payload and calls [onFrame] for every frame. Small frames come as [data];
  /// attachment bytes (type 4) come as a [stream] that must be consumed. Return false to stop.
  Future<void> _frames(
    String path,
    String password,
    Future<bool> Function(int type, Uint8List? data, Stream<List<int>>? stream) onFrame,
  ) async {
    final h = await _readHeader(path);
    final key = await _key(h.header, password);
    final reader = _ByteReader(crypto.sodium.crypto.secretStream.pullChunked(
      cipherStream: File(path).openRead(h.offset),
      key: key,
      chunkSize: _chunk,
    ));
    try {
      while (true) {
        final head = await reader.read(9);
        if (head == null) return;
        final bd = ByteData.sublistView(head);
        final type = bd.getUint8(0);
        final len = bd.getUint64(1, Endian.big);
        bool go;
        if (type == 4) {
          go = await onFrame(type, null, reader.stream(len));
          await reader.skipRest();
        } else {
          if (len > 16 * 1024 * 1024) throw BackupException('damaged file');
          final data = await reader.read(len);
          if (data == null) throw BackupException('truncated file');
          go = await onFrame(type, data, null);
        }
        if (!go) return;
      }
    } on BackupException {
      rethrow;
    } on StreamClosedEarlyException {
      throw BackupException('truncated file');
    } on SodiumException {
      throw BackupException('wrong password or damaged file');
    } catch (e) {
      if (e is StateError || e is FormatException) throw BackupException('wrong password or damaged file');
      rethrow;
    } finally {
      await reader.cancel();
      key.dispose();
    }
  }
}

/// Pull-style reader over a byte stream.
class _ByteReader {
  _ByteReader(Stream<List<int>> source) {
    _sub = source.listen(
      (chunk) {
        _buf.add(chunk);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
    _sub.pause();
  }

  late final StreamSubscription<List<int>> _sub;
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;
  int _streamLeft = 0;

  void _wake() {
    _sub.pause();
    _waiter?.complete();
    _waiter = null;
  }

  int get _available => _pending.length + _buf.length;

  Future<bool> _fill(int n) async {
    while (_available < n) {
      if (_error != null) throw _error!;
      if (_done) return false;
      _waiter = Completer<void>();
      _sub.resume();
      await _waiter!.future;
    }
    if (_error != null) throw _error!;
    return true;
  }

  Uint8List _take(int n) {
    if (_buf.length > 0) {
      _pending = Uint8List.fromList([..._pending, ..._buf.takeBytes()]);
    }
    final out = Uint8List.sublistView(_pending, 0, n);
    _pending = Uint8List.sublistView(_pending, n);
    return Uint8List.fromList(out);
  }

  Future<Uint8List?> read(int n) async {
    if (!await _fill(n)) {
      if (_available == 0) return null;
      throw StateError('truncated');
    }
    return _take(n);
  }

  /// A stream of exactly [length] bytes (consumed in pieces). What is not consumed is skipped by [skipRest].
  Stream<List<int>> stream(int length) {
    _streamLeft = length;
    return _streamGen();
  }

  Stream<List<int>> _streamGen() async* {
    while (_streamLeft > 0) {
      final n = _streamLeft < 65536 ? _streamLeft : 65536;
      final chunk = await read(n);
      if (chunk == null) throw StateError('truncated');
      _streamLeft -= chunk.length;
      yield chunk;
    }
  }

  /// Skips what the consumer of [stream] did not read.
  Future<void> skipRest() async {
    while (_streamLeft > 0) {
      final n = _streamLeft < 65536 ? _streamLeft : 65536;
      final chunk = await read(n);
      if (chunk == null) throw StateError('truncated');
      _streamLeft -= chunk.length;
    }
  }

  Future<void> cancel() => _sub.cancel();
}
