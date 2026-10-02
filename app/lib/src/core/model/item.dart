// The vault entry ("password" for the user) and its JSON form (docs/PROTOCOL.md §6).
import 'dart:convert';
import 'dart:typed_data';

import 'text_utils.dart';

/// One key/value row.
class Field {
  const Field({required this.id, required this.key, required this.value, this.hidden = false, this.link});

  final String id;
  final String key;
  final String value;

  /// The value is shown as dots (••••). Chosen by the user with the eye toggle, and saved.
  final bool hidden;

  /// Optional web address associated to the value ("text with a link").
  final String? link;

  Field copyWith({String? key, String? value, bool? hidden, String? link, bool clearLink = false}) => Field(
        id: id,
        key: key ?? this.key,
        value: value ?? this.value,
        hidden: hidden ?? this.hidden,
        link: clearLink ? null : (link ?? this.link),
      );

  /// The web address this row points to: its link, or the value itself if it is an address.
  Uri? get url {
    if (link != null) return Uri.tryParse(link!);
    return detectUrl(value, key: key);
  }

  bool get isEmailAddress => link == null && isEmail(value);

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': key,
        'v': value,
        if (hidden) 'h': true,
        if (link != null && link!.isNotEmpty) 'l': link,
      };

  factory Field.fromJson(Map<String, dynamic> j) => Field(
        id: j['id'] as String? ?? '',
        key: j['k'] as String? ?? '',
        value: j['v'] as String? ?? '',
        hidden: j['h'] == true,
        link: (j['l'] as String?)?.isNotEmpty == true ? j['l'] as String : null,
      );

  @override
  bool operator ==(Object other) =>
      other is Field && other.id == id && other.key == key && other.value == value && other.hidden == hidden && other.link == link;

  @override
  int get hashCode => Object.hash(id, key, value, hidden, link);
}

/// An attached file. The file itself is stored encrypted (blob [id]) with [key].
class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.key,
    required this.added,
  });

  final String id;
  final String name;
  final int size;
  final String mime;
  final Uint8List key;
  final DateTime added;

  bool get isImage => const {'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp'}.contains(mime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'mime': mime,
        'key': base64Url.encode(key),
        'added': added.millisecondsSinceEpoch,
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'file',
        size: (j['size'] as num?)?.toInt() ?? 0,
        mime: j['mime'] as String? ?? 'application/octet-stream',
        key: Uint8List.fromList(base64Url.decode(j['key'] as String)),
        added: DateTime.fromMillisecondsSinceEpoch((j['added'] as num?)?.toInt() ?? 0),
      );

  @override
  bool operator ==(Object other) => other is Attachment && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class Item {
  const Item({
    required this.id,
    required this.title,
    required this.fields,
    this.description = '',
    this.files = const [],
    this.favorite = false,
    this.trashedAt,
    required this.created,
    required this.updated,
    this.extra = const {},
  });

  final String id;
  final String title;
  final List<Field> fields;
  final String description;
  final List<Attachment> files;
  final bool favorite;
  final DateTime? trashedAt;
  final DateTime created;
  final DateTime updated;

  /// Unknown JSON keys, preserved for forward compatibility.
  final Map<String, dynamic> extra;

  bool get inTrash => trashedAt != null;

  List<String> get blobIds => [for (final f in files) f.id];

  Item copyWith({
    String? title,
    List<Field>? fields,
    String? description,
    List<Attachment>? files,
    bool? favorite,
    DateTime? trashedAt,
    bool restore = false,
    DateTime? updated,
    String? id,
  }) =>
      Item(
        id: id ?? this.id,
        title: title ?? this.title,
        fields: fields ?? this.fields,
        description: description ?? this.description,
        files: files ?? this.files,
        favorite: favorite ?? this.favorite,
        trashedAt: restore ? null : (trashedAt ?? this.trashedAt),
        created: created,
        updated: updated ?? this.updated,
        extra: extra,
      );

  /// First web address of the entry (links first in row order, then values).
  Uri? get website {
    for (final f in fields) {
      final u = f.url;
      if (u != null) return u;
    }
    return null;
  }

  static const _userKeys = ['email', 'e-mail', 'mail', 'utente', 'user', 'username', 'login', 'account', 'nome utente', 'id'];

  /// Shown under the title in the list: first visible username-like value.
  String get subtitle {
    for (final f in fields) {
      if (f.hidden) continue;
      final k = fold(f.key);
      if (_userKeys.any((u) => k == u || k.contains(u)) && f.value.trim().isNotEmpty) return f.value.trim();
    }
    for (final f in fields) {
      if (!f.hidden && isEmail(f.value)) return f.value.trim();
    }
    return '';
  }

  /// Accent- and case-insensitive search on title, keys, visible values, description and file names.
  /// Returns 2 for a title match, 1 for another match, 0 for none.
  int matchScore(String query) {
    final q = fold(query.trim());
    if (q.isEmpty) return 1;
    if (fold(title).contains(q)) return 2;
    for (final f in fields) {
      if (fold(f.key).contains(q)) return 1;
      if (!f.hidden && fold(f.value).contains(q)) return 1;
    }
    if (fold(description).contains(q)) return 1;
    if (files.any((a) => fold(a.name).contains(q))) return 1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'v': 1,
        'title': title,
        'fields': [for (final f in fields) f.toJson()],
        'desc': description,
        'files': [for (final a in files) a.toJson()],
        'fav': favorite,
        'trashed': trashedAt?.millisecondsSinceEpoch,
        'created': created.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
      };

  static const _known = {'v', 'title', 'fields', 'desc', 'files', 'fav', 'trashed', 'created', 'updated'};

  factory Item.fromJson(String id, Map<String, dynamic> j) => Item(
        id: id,
        title: j['title'] as String? ?? '',
        fields: [for (final f in (j['fields'] as List? ?? const [])) Field.fromJson(Map<String, dynamic>.from(f as Map))],
        description: j['desc'] as String? ?? '',
        files: [for (final a in (j['files'] as List? ?? const [])) Attachment.fromJson(Map<String, dynamic>.from(a as Map))],
        favorite: j['fav'] == true,
        trashedAt: j['trashed'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['trashed'] as num).toInt()),
        created: DateTime.fromMillisecondsSinceEpoch((j['created'] as num?)?.toInt() ?? 0),
        updated: DateTime.fromMillisecondsSinceEpoch((j['updated'] as num?)?.toInt() ?? 0),
        extra: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static Item decode(String id, Uint8List bytes) =>
      Item.fromJson(id, Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map));

  /// Content equality (ignores the update time), used to detect no-op conflicts.
  bool sameContent(Item o) =>
      o.title == title &&
      o.description == description &&
      o.favorite == favorite &&
      o.trashedAt == trashedAt &&
      _listEq(o.fields, fields) &&
      _listEq(o.files.map((f) => f.id).toList(), files.map((f) => f.id).toList());

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Alphabetical order by title (case- and accent-insensitive), then by creation.
int compareItems(Item a, Item b) {
  final c = fold(a.title).compareTo(fold(b.title));
  return c != 0 ? c : a.created.compareTo(b.created);
}
