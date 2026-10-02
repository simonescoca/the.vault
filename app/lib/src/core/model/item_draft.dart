// The editable form of an entry and the save rules of docs/SPEC.md §6.3.
import 'item.dart';
import 'text_utils.dart';

/// A row while editing.
class FieldDraft {
  FieldDraft({required this.id, this.key = '', this.value = '', this.hidden = false, this.link, this.suggestion});

  final String id;
  String key;
  String value;
  bool hidden;
  String? link;

  /// Grey suggestion shown in an empty key ("sito web", "email", "password"): it becomes the key
  /// if the user fills only the value.
  final String? suggestion;

  bool get isBlank => key.trim().isEmpty && value.trim().isEmpty && (link == null || link!.isEmpty);

  factory FieldDraft.fromField(Field f) => FieldDraft(id: f.id, key: f.key, value: f.value, hidden: f.hidden, link: f.link);

  FieldDraft copy() => FieldDraft(id: id, key: key, value: value, hidden: hidden, link: link, suggestion: suggestion);
}

sealed class SaveOutcome {}

class SaveOk extends SaveOutcome {
  SaveOk(this.item);
  final Item item;
}

/// The title is empty and no site name can be used instead.
class SaveNeedsTitle extends SaveOutcome {}

class ItemDraft {
  ItemDraft._({
    required this.originalId,
    required this.title,
    required this.fields,
    required this.description,
    required this.files,
    required this.favorite,
    required this.trashedAt,
    required this.created,
    required this.extra,
    required this.newFieldId,
  });

  /// Null for a new entry.
  final String? originalId;
  String title;
  final List<FieldDraft> fields;
  String description;
  final List<Attachment> files;
  bool favorite;
  final DateTime? trashedAt;
  final DateTime? created;
  final Map<String, dynamic> extra;
  final String Function() newFieldId;

  bool get isNew => originalId == null;

  /// A new entry: three empty rows with the suggested keys (e.g. website, email, password).
  factory ItemDraft.blank(List<String> suggestions, String Function() newFieldId) => ItemDraft._(
        originalId: null,
        title: '',
        fields: [for (final s in suggestions) FieldDraft(id: newFieldId(), suggestion: s)],
        description: '',
        files: [],
        favorite: false,
        trashedAt: null,
        created: null,
        extra: const {},
        newFieldId: newFieldId,
      );

  /// Editing an existing entry. An entry without rows gets one empty row (at least one is always shown).
  factory ItemDraft.fromItem(Item item, String Function() newFieldId) {
    final rows = [for (final f in item.fields) FieldDraft.fromField(f)];
    if (rows.isEmpty) rows.add(FieldDraft(id: newFieldId()));
    return ItemDraft._(
      originalId: item.id,
      title: item.title,
      fields: rows,
      description: item.description,
      files: [...item.files],
      favorite: item.favorite,
      trashedAt: item.trashedAt,
      created: item.created,
      extra: item.extra,
      newFieldId: newFieldId,
    );
  }

  bool get canRemoveRow => fields.length > 1;

  FieldDraft addRow({int? at}) {
    final f = FieldDraft(id: newFieldId());
    fields.insert(at ?? fields.length, f);
    return f;
  }

  /// Removes a row, unless it is the last one.
  bool removeRow(String id) {
    if (!canRemoveRow) return false;
    final before = fields.length;
    fields.removeWhere((f) => f.id == id);
    return fields.length != before;
  }

  /// Moves a row (indexes as in ReorderableList: [newIndex] counted before removal).
  void moveRow(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= fields.length) return;
    var to = newIndex;
    if (to > oldIndex) to -= 1;
    to = to.clamp(0, fields.length - 1);
    final f = fields.removeAt(oldIndex);
    fields.insert(to, f);
  }

  /// Moves a row to [newIndex], counted after the row has been removed from [oldIndex].
  void moveRowTo(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= fields.length) return;
    final f = fields.removeAt(oldIndex);
    fields.insert(newIndex.clamp(0, fields.length), f);
  }

  /// Site name proposed as title while the title is empty ("Netflix").
  String? get titleSuggestion {
    for (final f in fields) {
      if (f.value.trim().isEmpty) continue;
      final link = f.link == null ? null : normalizeLink(f.link!);
      final u = link != null ? Uri.tryParse(link) : detectUrl(f.value, key: f.key.isEmpty ? (f.suggestion ?? '') : f.key);
      if (u != null) {
        final name = siteName(u);
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// Applies the save rules and builds the entry.
  SaveOutcome build({required String id, required DateTime now}) {
    final rows = <Field>[];
    for (final f in fields) {
      if (f.value.trim().isEmpty) continue; // empty value → row removed (with or without key)
      var key = f.key.trim();
      if (key.isEmpty && f.suggestion != null) key = f.suggestion!;
      final link = f.link == null ? null : normalizeLink(f.link!);
      rows.add(Field(id: f.id, key: key, value: f.value, hidden: f.hidden, link: link));
    }
    var t = title.trim();
    if (t.isEmpty) {
      final suggestion = titleSuggestion;
      if (suggestion == null) return SaveNeedsTitle();
      t = suggestion;
    }
    return SaveOk(Item(
      id: originalId ?? id,
      title: t,
      fields: rows,
      description: description.trim(),
      files: [...files],
      favorite: favorite,
      trashedAt: trashedAt,
      created: created ?? now,
      updated: now,
      extra: extra,
    ));
  }
}
