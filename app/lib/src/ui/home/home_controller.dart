// UI state of the main window: section, search, selection, editing.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/model/item.dart';
import '../../core/model/item_draft.dart';
import '../../core/vault/vault_controller.dart';

/// Result of trying to save the entry being edited.
enum SaveResult { saved, needsTitle, conflict }

class HomeController extends ChangeNotifier {
  HomeController(this.vault) {
    vault.addListener(_vaultChanged);
  }

  final VaultController vault;

  Section section = Section.all;
  String query = '';
  String? selectedId;

  /// The entry being created or edited (null when viewing).
  ItemDraft? draft;

  /// Server revision of the entry when editing started (to detect changes made elsewhere).
  int draftBaseRev = 0;

  /// Bumped by the editor on every change (to know whether there is something to lose).
  bool dirty = false;

  bool get editing => draft != null;

  static String fieldId() => const Uuid().v4().substring(0, 8);

  List<Item> get visible => vault.list(section, query: query);

  Item? get selected => selectedId == null ? null : vault.byId(selectedId!);

  void _vaultChanged() {
    if (selectedId != null && vault.byId(selectedId!) == null && !editing) selectedId = null;
    notifyListeners();
  }

  void setSection(Section s) {
    section = s;
    query = '';
    final v = visible;
    if (selectedId == null || !v.any((i) => i.id == selectedId)) {
      selectedId = v.isEmpty ? null : v.first.id;
    }
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    final v = visible;
    if (q.isNotEmpty && v.isNotEmpty && !v.any((i) => i.id == selectedId)) selectedId = v.first.id;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void moveSelection(int delta) {
    final v = visible;
    if (v.isEmpty) return;
    final i = v.indexWhere((x) => x.id == selectedId);
    final next = (i < 0 ? 0 : i + delta).clamp(0, v.length - 1);
    selectedId = v[next].id;
    notifyListeners();
  }

  void startNew(List<String> suggestions) {
    if (section == Section.trash) section = Section.all;
    draft = ItemDraft.blank(suggestions, fieldId);
    draftBaseRev = 0;
    dirty = false;
    notifyListeners();
  }

  void startEdit() {
    final it = selected;
    if (it == null || it.inTrash) return;
    draft = ItemDraft.fromItem(it, fieldId);
    draftBaseRev = vault.knownRevision(it.id);
    dirty = false;
    notifyListeners();
  }

  void cancelEdit() {
    final d = draft;
    if (d != null) {
      // Attachments added during a cancelled edit are no longer protected (cleaned up later).
      final kept = d.isNew ? <String>{} : (vault.byId(d.originalId!)?.blobIds.toSet() ?? <String>{});
      for (final f in d.files) {
        if (!kept.contains(f.id)) vault.sync.protectedBlobs.remove(f.id);
      }
    }
    draft = null;
    dirty = false;
    notifyListeners();
  }

  void markDirty() {
    if (!dirty) {
      dirty = true;
      notifyListeners();
    }
  }

  /// Saves the draft. With [force] (after the user chose "overwrite") the change is saved even if
  /// the entry changed on another device meanwhile; with [asCopy] it is saved as a new entry.
  SaveResult save({bool force = false, bool asCopy = false}) {
    final d = draft;
    if (d == null) return SaveResult.saved;
    final r = d.build(id: VaultController.newId(), now: DateTime.now());
    if (r is SaveNeedsTitle) return SaveResult.needsTitle;
    final item = (r as SaveOk).item;
    if (!d.isNew && !force && !asCopy && vault.knownRevision(item.id) != draftBaseRev) {
      return SaveResult.conflict;
    }
    final Item saved;
    if (asCopy) {
      saved = vault.saveAsCopy(item);
    } else {
      vault.save(item);
      saved = item;
    }
    selectedId = saved.id;
    draft = null;
    dirty = false;
    notifyListeners();
    return SaveResult.saved;
  }

  @override
  void dispose() {
    vault.removeListener(_vaultChanged);
    super.dispose();
  }
}
