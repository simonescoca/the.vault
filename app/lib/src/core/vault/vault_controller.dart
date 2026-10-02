// The unlocked vault: decrypted entries in memory, every change encrypted and queued for sync.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../crypto/file_crypto.dart';
import '../crypto/vault_crypto.dart';
import '../model/item.dart';
import '../storage/local_db.dart';
import '../sync/sync_engine.dart';

enum Section { all, favorites, trash }

/// Something the UI should tell the user about (shown as a short message).
enum VaultNotice { conflictCopy }

class VaultController extends ChangeNotifier {
  VaultController({
    required this.crypto,
    required this.db,
    required this.sync,
    this.conflictSuffix = ' (conflitto)',
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    sync.onConflict = resolveConflict;
    sync.onChanged = (ids) => _reload(ids);
  }

  final VaultCrypto crypto;
  final LocalDb db;
  final SyncEngine sync;
  String conflictSuffix;
  final DateTime Function() _now;

  final _notices = StreamController<VaultNotice>.broadcast();
  Stream<VaultNotice> get notices => _notices.stream;

  SecureKey? _vaultKey;
  SecureKey? _itemsKey;
  CacheCipher? _cache;
  final Map<String, Item> _items = {};

  /// Records that could not be decrypted (should never happen; shown nowhere, kept for diagnostics).
  final Set<String> broken = {};

  static String newId() => const Uuid().v4();

  bool get isUnlocked => _itemsKey != null;

  SecureKey get vaultKey {
    final k = _vaultKey;
    if (k == null) throw StateError('vault locked');
    return k;
  }

  /// Encrypts the local caches (site icons); null while locked.
  CacheCipher? get cache => _cache;

  /// Opens the vault with its key (the controller takes ownership of [vk]).
  void unlock(SecureKey vk) {
    lock(notify: false);
    _vaultKey = vk;
    _itemsKey = crypto.itemsKey(vk);
    _cache = CacheCipher(crypto, crypto.cacheKey(vk));
    _reloadAll();
  }

  /// Forgets the key and every decrypted entry.
  void lock({bool notify = true}) {
    _items.clear();
    _itemsKey?.dispose();
    _vaultKey?.dispose();
    _cache?._key.dispose();
    _itemsKey = null;
    _vaultKey = null;
    _cache = null;
    if (notify) notifyListeners();
  }

  // ------------------------------------------------------------- reading

  Item? _decrypt(String id, Uint8List data) {
    final k = _itemsKey;
    if (k == null) return null;
    try {
      return Item.decode(id, crypto.decryptRecord(k, id, data));
    } catch (e) {
      broken.add(id);
      debugPrint('cannot decrypt record $id: $e');
      return null;
    }
  }

  void _reloadAll() {
    _items.clear();
    for (final e in db.effective().entries) {
      final it = _decrypt(e.key, e.value.data);
      if (it != null) _items[e.key] = it;
    }
    notifyListeners();
  }

  void _reload(Set<String> ids) {
    if (!isUnlocked) return;
    final eff = db.effective();
    for (final id in ids) {
      final e = eff[id];
      if (e == null) {
        _items.remove(id);
      } else {
        final it = _decrypt(id, e.data);
        if (it != null) _items[id] = it;
      }
    }
    notifyListeners();
  }

  Item? byId(String id) => _items[id];

  Iterable<Item> get _live => _items.values.where((i) => !i.inTrash);

  int count(Section s) => switch (s) {
        Section.all => _live.length,
        Section.favorites => _live.where((i) => i.favorite).length,
        Section.trash => _items.values.where((i) => i.inTrash).length,
      };

  /// Entries of a section filtered by [query]: alphabetical, title matches first when searching.
  List<Item> list(Section s, {String query = ''}) {
    final base = switch (s) {
      Section.all => _live,
      Section.favorites => _live.where((i) => i.favorite),
      Section.trash => _items.values.where((i) => i.inTrash),
    };
    if (query.trim().isEmpty) {
      final out = base.toList()..sort(compareItems);
      if (s == Section.trash) out.sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));
      return out;
    }
    final scored = [
      for (final i in base)
        if (i.matchScore(query) > 0) (i, i.matchScore(query)),
    ]..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : compareItems(a.$1, b.$1));
    return [for (final e in scored) e.$1];
  }

  /// Server revision currently known for an entry (to detect changes made elsewhere while editing).
  int knownRevision(String id) => db.record(id)?.rev ?? 0;

  // ------------------------------------------------------------- writing

  void _queue(Item item) {
    final k = _itemsKey;
    if (k == null) throw StateError('vault locked');
    final data = crypto.encryptRecord(k, item.id, item.encode());
    db.putPending(id: item.id, op: 'put', data: data, blobs: item.blobIds);
    _items[item.id] = item;
    for (final b in item.blobIds) {
      sync.protectedBlobs.remove(b);
    }
    notifyListeners();
    unawaited(sync.sync());
  }

  /// Saves a created or edited entry.
  void save(Item item) => _queue(item.copyWith(updated: _now()));

  /// Saves [item] as a new entry (used by "keep both" in the edit-conflict dialog).
  Item saveAsCopy(Item item) {
    final copy = item.copyWith(id: newId(), title: '${item.title}$conflictSuffix', updated: _now());
    _queue(copy);
    return copy;
  }

  void setFavorite(String id, bool favorite) {
    final it = _items[id];
    if (it == null || it.favorite == favorite) return;
    _queue(it.copyWith(favorite: favorite, updated: _now()));
  }

  /// The eye toggle: hides/shows a value, and the choice is saved.
  void setHidden(String id, String fieldId, bool hidden) {
    final it = _items[id];
    if (it == null) return;
    final fields = [for (final f in it.fields) f.id == fieldId ? f.copyWith(hidden: hidden) : f];
    _queue(it.copyWith(fields: fields, updated: _now()));
  }

  void moveToTrash(String id) {
    final it = _items[id];
    if (it == null || it.inTrash) return;
    _queue(it.copyWith(trashedAt: _now(), updated: _now()));
  }

  void restore(String id) {
    final it = _items[id];
    if (it == null || !it.inTrash) return;
    _queue(it.copyWith(restore: true, updated: _now()));
  }

  /// Permanent deletion (only from the trash).
  void deleteForever(String id) {
    final it = _items[id];
    if (it == null || !it.inTrash) return;
    db.putPending(id: id, op: 'delete');
    _items.remove(id);
    notifyListeners();
    unawaited(sync.sync());
  }

  void emptyTrash() {
    final ids = [for (final i in _items.values) if (i.inTrash) i.id];
    for (final id in ids) {
      db.putPending(id: id, op: 'delete');
      _items.remove(id);
    }
    if (ids.isNotEmpty) {
      notifyListeners();
      unawaited(sync.sync());
    }
  }

  // ----------------------------------------------------------- conflicts

  Future<bool> resolveConflict(PendingRow local, RecordRow? base, RecordRow current) async {
    if (!isUnlocked) return false;
    if (local.isDelete) {
      // Deleted here, changed (or already deleted) there: never lose data silently → keep theirs.
      db.dropPending(local.id);
      _reload({local.id});
      return true;
    }
    final mine = _decrypt(local.id, local.data!);
    if (mine == null) {
      db.dropPending(local.id);
      return true;
    }
    if (current.deleted || current.data == null) {
      // Deleted elsewhere while edited here: bring our version back as a new entry.
      _requeueAs(mine.copyWith(id: newId()), local.id);
      return true;
    }
    final theirs = _decrypt(current.id, current.data!);
    if (theirs == null) {
      db.rebasePending(local.id, current.rev);
      return true;
    }
    if (theirs.sameContent(mine)) {
      db.dropPending(local.id);
      _reload({local.id});
      return true;
    }
    // Three-way merge of the simple cases: one side only toggled favorite / hidden values.
    final b = (base != null && base.rev == local.baseRev && base.data != null) ? _decrypt(base.id, base.data!) : null;
    if (b != null) {
      final merged = _mergeFlags(b, mine, theirs);
      if (merged != null) {
        final k = _itemsKey!;
        db.dropPending(local.id);
        db.putPending(id: local.id, op: 'put', data: crypto.encryptRecord(k, local.id, merged.encode()), blobs: merged.blobIds);
        _items[local.id] = merged;
        notifyListeners();
        return true;
      }
    }
    // Real conflict: theirs stays, ours becomes a copy.
    _requeueAs(mine.copyWith(id: newId(), title: '${mine.title}$conflictSuffix'), local.id);
    _notices.add(VaultNotice.conflictCopy);
    return true;
  }

  void _requeueAs(Item copy, String originalId) {
    final k = _itemsKey!;
    db.dropPending(originalId);
    db.putPending(id: copy.id, op: 'put', data: crypto.encryptRecord(k, copy.id, copy.encode()), blobs: copy.blobIds);
    _items[copy.id] = copy;
    _reload({originalId});
  }

  /// If one side changed only the favorite flag and/or the hidden flags, applies those changes on
  /// top of the other side. Returns null when both changed real content.
  Item? _mergeFlags(Item base, Item mine, Item theirs) {
    bool onlyFlags(Item a, Item b) =>
        a.title == b.title &&
        a.description == b.description &&
        a.trashedAt == b.trashedAt &&
        a.files.map((f) => f.id).join() == b.files.map((f) => f.id).join() &&
        a.fields.length == b.fields.length &&
        [for (var i = 0; i < a.fields.length; i++) i].every((i) =>
            a.fields[i].id == b.fields[i].id &&
            a.fields[i].key == b.fields[i].key &&
            a.fields[i].value == b.fields[i].value &&
            a.fields[i].link == b.fields[i].link);
    Item apply(Item target, Item flagsFrom) {
      final hidden = {for (final f in flagsFrom.fields) f.id: f.hidden};
      final baseHidden = {for (final f in base.fields) f.id: f.hidden};
      return target.copyWith(
        favorite: flagsFrom.favorite != base.favorite ? flagsFrom.favorite : target.favorite,
        fields: [
          for (final f in target.fields)
            (hidden.containsKey(f.id) && hidden[f.id] != baseHidden[f.id]) ? f.copyWith(hidden: hidden[f.id]) : f,
        ],
        updated: _now(),
      );
    }

    if (onlyFlags(base, mine)) return apply(theirs, mine);
    if (onlyFlags(base, theirs)) return apply(mine, theirs);
    return null;
  }

  // --------------------------------------------------------- attachments

  /// Encrypts a file into the local store and returns its attachment (to be added to a draft).
  Future<Attachment> addAttachment(File source, {String? mime}) async {
    final id = newId();
    final key = FileCrypto.newKey(crypto);
    await sync.blobs.ensure();
    sync.protectedBlobs.add(id);
    await FileCrypto.encryptFile(source.path, sync.blobs.file(id).path, key);
    await sync.addLocalBlob(id, await sync.blobs.file(id).length());
    return Attachment(
      id: id,
      name: p.basename(source.path),
      size: await source.length(),
      mime: mime ?? mimeFor(source.path),
      key: key,
      added: _now(),
    );
  }

  /// Decrypts an attachment into [dir] (downloading it first if needed) and returns the file.
  Future<File> exportAttachment(Attachment a, String dir) async {
    if (!await sync.blobs.file(a.id).exists()) await sync.downloadBlob(a.id);
    final folder = Directory(p.join(dir, a.id));
    await folder.create(recursive: true);
    final out = File(p.join(folder.path, _safeName(a.name)));
    await FileCrypto.decryptFile(sync.blobs.file(a.id).path, out.path, a.key);
    return out;
  }

  /// Decrypted bytes of a small attachment (image previews).
  Future<Uint8List?> attachmentBytes(Attachment a) async {
    final f = sync.blobs.file(a.id);
    if (!await f.exists() || a.size > 20 * 1024 * 1024) return null;
    return FileCrypto.decryptBytes(crypto.sodium, await f.readAsBytes(), a.key);
  }

  static String _safeName(String name) {
    final n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return n.isEmpty ? 'file' : n;
  }

  @override
  void dispose() {
    lock(notify: false);
    _notices.close();
    super.dispose();
  }
}

const _mimes = {
  'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif',
  'webp': 'image/webp', 'bmp': 'image/bmp', 'heic': 'image/heic', 'txt': 'text/plain', 'md': 'text/markdown',
  'csv': 'text/csv', 'json': 'application/json', 'zip': 'application/zip', 'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'key': 'application/vnd.apple.keynote', 'pages': 'application/vnd.apple.pages', 'numbers': 'application/vnd.apple.numbers',
  'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'wav': 'audio/wav', 'mp4': 'video/mp4', 'mov': 'video/quicktime',
  'pem': 'application/x-pem-file', 'p12': 'application/x-pkcs12', 'pfx': 'application/x-pkcs12',
};

String mimeFor(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return _mimes[ext] ?? 'application/octet-stream';
}

/// Encryption of the local caches with a key derived from the vault key (see [VaultCrypto.cacheName]).
/// After the vault locks its key is gone and every call fails.
class CacheCipher {
  CacheCipher(this._crypto, this._key);
  final VaultCrypto _crypto;
  final SecureKey _key;

  String name(String kind, String plainName) => _crypto.cacheName(_key, kind, plainName);
  Uint8List seal(String storedName, Uint8List data) => _crypto.sealCache(_key, storedName, data);
  Uint8List open(String storedName, Uint8List data) => _crypto.openCache(_key, storedName, data);
}
