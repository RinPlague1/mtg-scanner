import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'collection_query.dart';
import 'json_file.dart';
import 'models.dart';
import 'scryfall.dart';

class CollectionEntry {
  /// Replaced when card details are refreshed (same printing id).
  CardPrint card;
  final bool foil;
  final Binder binder;
  final CardCondition condition;
  int quantity;
  final DateTime added;

  /// Your own labels, e.g. "Aang staples", "To sell". Not part of the
  /// entry's identity: moving copies keeps their tags.
  final Set<String> tags;

  /// Folder inside the binder ("Sharks", "Box 3"), or null for unsorted.
  final String? folder;

  CollectionEntry(
    this.card, {
    this.foil = false,
    this.quantity = 1,
    this.binder = Binder.collection,
    this.condition = CardCondition.nm,
    DateTime? added,
    Set<String>? tags,
    this.folder,
  })  : added = added ?? DateTime.now(),
        tags = tags ?? {};

  static String keyFor(CardPrint card, bool foil, Binder binder, CardCondition condition, [String? folder]) =>
      '${card.id}|${foil ? 'f' : 'n'}|${binder.id}|${condition.code}${folder == null ? '' : '|$folder'}';

  String get key => keyFor(card, foil, binder, condition, folder);

  CollectionEntry copyWith({CardPrint? card, bool? foil, int? quantity, Binder? binder, CardCondition? condition,
          String? folder, bool clearFolder = false}) =>
      CollectionEntry(card ?? this.card,
          foil: foil ?? this.foil,
          quantity: quantity ?? this.quantity,
          binder: binder ?? this.binder,
          condition: condition ?? this.condition,
          added: added,
          tags: {...tags},
          folder: clearFolder ? null : (folder ?? this.folder));
  String get nameKey => nameKeyOf(card);

  double? get priceEur => double.tryParse((foil ? card.priceEurFoil : card.priceEur) ?? '');
  double? get priceUsd => double.tryParse((foil ? card.priceUsdFoil : card.priceUsd) ?? '');

  Map<String, dynamic> toJson() => {
        'card': card.toJson(),
        'foil': foil,
        'quantity': quantity,
        'binder': binder.id,
        'condition': condition.code,
        'added': added.toIso8601String(),
        if (tags.isNotEmpty) 'tags': tags.toList()..sort(),
        if (folder != null) 'folder': folder,
      };

  /// Row shape for the server (see supabase/schema.sql → replace_my_collection).
  Map<String, dynamic> toServerJson() => {
        'item_key': key,
        'card': card.toJson(),
        'name_key': nameKey,
        'foil': foil,
        'qty': quantity,
        'binder': binder.id,
        'condition': condition.code,
        'added': added.toUtc().toIso8601String(),
        'tags': tags.toList()..sort(),
        'folder': folder,
      };

  factory CollectionEntry.fromJson(Map<String, dynamic> j) => CollectionEntry(
        CardPrint.fromScryfall(j['card'] as Map<String, dynamic>),
        foil: j['foil'] as bool? ?? false,
        quantity: (j['quantity'] ?? j['qty']) as int? ?? 1,
        binder: Binder.parse(j['binder'] as String?),
        condition: CardCondition.parse(j['condition'] as String?),
        added: DateTime.tryParse(j['added'] as String? ?? ''),
        tags: ((j['tags'] as List?) ?? const []).cast<String>().toSet(),
        folder: j['folder'] as String?,
      );
}

String nameKeyOf(CardPrint c) => nameKey(c.name);

/// Local collection persisted as JSON in the app's documents folder. The phone
/// is the source of truth; when signed in, SyncService mirrors it to Supabase.
class CollectionStore extends ChangeNotifier {
  final List<CollectionEntry> _entries = [];
  final JsonFile _file = JsonFile('collection.json');
  final JsonFile _foldersFile = JsonFile('folders.json');
  final List<CollectionFolder> _folders = [];

  /// Folder definitions (names, auto-sort rules), in display order.
  List<CollectionFolder> get folders => List.unmodifiable(_folders);

  List<CollectionEntry> get entries => List.unmodifiable(_entries);
  int get totalCards => _entries.fold(0, (s, e) => s + e.quantity);
  double get totalEur => _entries.fold(0.0, (s, e) => s + (e.priceEur ?? 0) * e.quantity);
  bool get isEmpty => _entries.isEmpty;

  List<CollectionEntry> inBinder(Binder b) => _entries.where((e) => e.binder == b).toList();
  int countIn(Binder b) => _entries.where((e) => e.binder == b).fold(0, (s, e) => s + e.quantity);

  /// Total copies owned of a card name, across all binders and printings.
  int ownedCount(String key) =>
      _entries.where((e) => e.nameKey == key).fold(0, (s, e) => s + e.quantity);

  Future<void> load() async {
    final f = await _foldersFile.open();
    if (f is List) {
      _folders
        ..clear()
        ..addAll(f.map((x) => CollectionFolder.fromJson(x as Map<String, dynamic>)));
    }
    final data = await _file.open();
    if (data is List) {
      _entries
        ..clear()
        ..addAll(data.map((e) => CollectionEntry.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write(_entries.map((e) => e.toJson()).toList());

  void _merge(CardPrint card, bool foil, int quantity, Binder binder, CardCondition condition,
      {bool toFront = true, Set<String> tags = const {}, String? folder}) {
    // New cards go into the first auto-sorting folder whose rule they match.
    folder ??= autoFolderFor(CollectionEntry(card, foil: foil, binder: binder, condition: condition, tags: tags));
    final key = CollectionEntry.keyFor(card, foil, binder, condition, folder);
    final i = _entries.indexWhere((e) => e.key == key);
    if (i >= 0) {
      _entries[i].quantity += quantity;
      _entries[i].tags.addAll(tags);
      if (toFront) {
        final e = _entries.removeAt(i);
        _entries.insert(0, e); // most recent first
      }
    } else {
      _entries.insert(
          0,
          CollectionEntry(card,
              foil: foil, quantity: quantity, binder: binder, condition: condition, tags: {...tags}, folder: folder));
    }
  }

  Future<void> add(
    CardPrint card, {
    bool foil = false,
    int quantity = 1,
    Binder binder = Binder.collection,
    CardCondition condition = CardCondition.nm,
  }) async {
    _merge(card, foil, quantity, binder, condition);
    notifyListeners();
    await _save();
  }

  /// Bulk add (imports). One save and one notification.
  Future<void> addAll(Iterable<CollectionEntry> items) async {
    for (final e in items) {
      _merge(e.card, e.foil, e.quantity, e.binder, e.condition, tags: e.tags, folder: e.folder);
    }
    notifyListeners();
    await _save();
  }

  Future<void> setQuantity(CollectionEntry e, int q) async {
    if (q <= 0) {
      _entries.remove(e);
    } else {
      e.quantity = q;
    }
    notifyListeners();
    await _save();
  }

  /// Move [qty] copies of [e] to another binder and/or condition.
  Future<void> move(CollectionEntry e, int qty, {Binder? binder, CardCondition? condition}) async {
    if (!_moveNoSave(e, qty, binder: binder, condition: condition)) return;
    notifyListeners();
    await _save();
  }

  bool _moveNoSave(CollectionEntry e, int qty, {Binder? binder, CardCondition? condition}) {
    final n = qty.clamp(0, e.quantity);
    if (n == 0) return false;
    final b = binder ?? e.binder;
    final c = condition ?? e.condition;
    if (b == e.binder && c == e.condition) return false;
    final index = _entries.indexOf(e);
    e.quantity -= n;
    if (e.quantity == 0) _entries.remove(e);
    // Folders belong to a binder: moving binder leaves the folder behind.
    final folder = b == e.binder ? e.folder : null;
    final key = CollectionEntry.keyFor(e.card, e.foil, b, c, folder);
    final existing = _entries.where((x) => x.key == key).firstOrNull;
    if (existing != null) {
      existing.quantity += n;
      existing.tags.addAll(e.tags);
    } else {
      final moved = CollectionEntry(e.card,
          foil: e.foil, quantity: n, binder: b, condition: c, added: e.added, tags: {...e.tags}, folder: folder);
      _entries.insert(index.clamp(0, _entries.length), moved);
    }
    return true;
  }

  /// Switch every copy of [e] to another printing and/or finish. Merges into
  /// an existing entry with the same printing, finish, binder and condition.
  /// Returns the entry that now holds the copies.
  Future<CollectionEntry> changePrinting(CollectionEntry e, CardPrint card, {bool? foil}) async {
    final f = foil ?? e.foil;
    if (card.id == e.card.id && f == e.foil) return e;
    final index = _entries.indexOf(e);
    _entries.remove(e);
    final key = CollectionEntry.keyFor(card, f, e.binder, e.condition, e.folder);
    var result = _entries.where((x) => x.key == key).firstOrNull;
    if (result != null) {
      result.quantity += e.quantity;
      result.tags.addAll(e.tags);
    } else {
      result = CollectionEntry(card,
          foil: f,
          quantity: e.quantity,
          binder: e.binder,
          condition: e.condition,
          added: e.added,
          tags: {...e.tags},
          folder: e.folder);
      _entries.insert(index.clamp(0, _entries.length), result);
    }
    notifyListeners();
    await _save();
    return result;
  }

  // ───────── Bulk edits (multi-select) ─────────

  /// Move every copy of each entry to [binder] and/or [condition].
  Future<void> moveAll(Iterable<CollectionEntry> items, {Binder? binder, CardCondition? condition}) async {
    var changed = false;
    for (final e in items.toList()) {
      changed = _moveNoSave(e, e.quantity, binder: binder, condition: condition) || changed;
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  /// Replace entries with edited copies, merging any that now share a key.
  void _replaceAllNoSave(Iterable<CollectionEntry> items, CollectionEntry Function(CollectionEntry) edit) {
    for (final e in items.toList()) {
      final i = _entries.indexOf(e);
      if (i < 0) continue;
      final next = edit(e);
      if (next.key == e.key) continue;
      _entries.removeAt(i);
      final existing = _entries.where((x) => x.key == next.key).firstOrNull;
      if (existing != null) {
        existing.quantity += next.quantity;
        existing.tags.addAll(next.tags);
      } else {
        _entries.insert(i.clamp(0, _entries.length), next);
      }
    }
  }

  /// Set foil / non-foil on many entries.
  Future<void> setFoilAll(Iterable<CollectionEntry> items, bool foil) async {
    _replaceAllNoSave(items, (e) => e.copyWith(foil: foil));
    notifyListeners();
    await _save();
  }

  /// Put entries into [folder] (null = unsorted). Cards stay in their binder.
  Future<void> setFolderAll(Iterable<CollectionEntry> items, String? folder) async {
    _replaceAllNoSave(items, (e) => e.copyWith(folder: folder, clearFolder: folder == null));
    notifyListeners();
    await _save();
  }

  // ───────── Folders ─────────

  Future<void> _saveFolders() => _foldersFile.write(_folders.map((f) => f.toJson()).toList());

  List<CollectionFolder> foldersIn(Binder b) => _folders.where((f) => f.binder == b).toList();

  int countInFolder(Binder b, String? folder) =>
      _entries.where((e) => e.binder == b && e.folder == folder).fold(0, (n, e) => n + e.quantity);

  CollectionFolder? folderNamed(Binder b, String name) =>
      _folders.where((f) => f.binder == b && f.name == name).firstOrNull;

  /// The first auto-sorting folder in [e]'s binder whose rule matches.
  String? autoFolderFor(CollectionEntry e) {
    for (final f in _folders) {
      if (f.binder == e.binder && f.autoSort && f.rule != null && f.rule!.matches(e)) return f.name;
    }
    return null;
  }

  Future<void> saveFolder(CollectionFolder folder, {String? oldName}) async {
    final i = _folders.indexWhere((f) => f.binder == folder.binder && f.name == (oldName ?? folder.name));
    if (i >= 0) {
      _folders[i] = folder;
    } else {
      _folders.add(folder);
    }
    if (oldName != null && oldName != folder.name) {
      _replaceAllNoSave(_entries.where((e) => e.binder == folder.binder && e.folder == oldName),
          (e) => e.copyWith(folder: folder.name));
      await _save();
    }
    notifyListeners();
    await _saveFolders();
  }

  /// Delete a folder; its cards go back to unsorted.
  Future<void> deleteFolder(CollectionFolder folder) async {
    _folders.remove(folder);
    _replaceAllNoSave(_entries.where((e) => e.binder == folder.binder && e.folder == folder.name),
        (e) => e.copyWith(clearFolder: true));
    notifyListeners();
    await _saveFolders();
    await _save();
  }

  /// Move unsorted cards in the folder's binder that match its rule into it.
  /// With [includeSorted], cards already in other folders move too.
  Future<int> sortIntoFolder(CollectionFolder folder, {bool includeSorted = false}) async {
    final rule = folder.rule;
    if (rule == null) return 0;
    final hits = _entries
        .where((e) =>
            e.binder == folder.binder &&
            e.folder != folder.name &&
            (includeSorted || e.folder == null) &&
            rule.matches(e))
        .toList();
    final n = hits.fold(0, (s, e) => s + e.quantity);
    _replaceAllNoSave(hits, (e) => e.copyWith(folder: folder.name));
    notifyListeners();
    await _save();
    return n;
  }

  Future<void> removeAll(Iterable<CollectionEntry> items) async {
    final set = items.toSet();
    _entries.removeWhere(set.contains);
    notifyListeners();
    await _save();
  }

  // ───────── Tags ─────────

  /// Every tag in use, alphabetical.
  List<String> get allTags {
    final s = <String>{for (final e in _entries) ...e.tags};
    return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  int countTagged(String tag) =>
      _entries.where((e) => e.tags.contains(tag)).fold(0, (n, e) => n + e.quantity);

  Future<void> tagAll(Iterable<CollectionEntry> items, {Set<String> add = const {}, Set<String> remove = const {}}) async {
    for (final e in items) {
      e.tags
        ..removeAll(remove)
        ..addAll(add);
    }
    notifyListeners();
    await _save();
  }

  Future<void> renameTag(String from, String to) async {
    final name = to.trim();
    if (name.isEmpty || name == from) return;
    for (final e in _entries) {
      if (e.tags.remove(from)) e.tags.add(name);
    }
    notifyListeners();
    await _save();
  }

  Future<void> deleteTag(String tag) async {
    for (final e in _entries) {
      e.tags.remove(tag);
    }
    notifyListeners();
    await _save();
  }

  // ───────── Card details ─────────

  int get missingDetails => _entries.where((e) => !e.card.hasDetails && !e.card.id.startsWith('trade-')).length;

  /// Fill in colour, type and mana value for cards saved before those were
  /// stored. Looks up each printing on Scryfall (75 per request). Returns how
  /// many entries were updated.
  Future<int> refreshDetails(ScryfallClient scryfall) async {
    final need = _entries.where((e) => !e.card.hasDetails && !e.card.id.startsWith('trade-')).toList();
    if (need.isEmpty) return 0;
    final ids = {for (final e in need) e.card.id};
    final cards = await scryfall.collection(ids.map((id) => {'id': id}).toList());
    final byId = {for (final c in cards) c.id: c};
    var n = 0;
    for (final e in need) {
      final fresh = byId[e.card.id];
      if (fresh != null) {
        e.card = fresh;
        n++;
      }
    }
    notifyListeners();
    await _save();
    return n;
  }

  /// Re-fetch prices (and details) for every printing you own. Uses the
  /// offline card data when downloaded (its prices are up to a week old),
  /// otherwise Scryfall, 75 cards per request. Returns how many updated.
  Future<int> refreshPrices(ScryfallClient scryfall, {void Function(int done, int total)? onProgress}) async {
    final need = _entries.where((e) => !e.card.id.startsWith('trade-')).toList();
    if (need.isEmpty) return 0;
    final ids = {for (final e in need) e.card.id};
    final cards = await scryfall.collection(ids.map((id) => {'id': id}).toList(), onProgress: onProgress);
    final byId = {for (final c in cards) c.id: c};
    var n = 0;
    for (final e in need) {
      final fresh = byId[e.card.id];
      if (fresh != null) {
        e.card = fresh;
        n++;
      }
    }
    notifyListeners();
    await _save();
    return n;
  }

  /// Replace everything (restore from the server on a new phone).
  Future<void> replaceAll(List<CollectionEntry> items) async {
    _entries
      ..clear()
      ..addAll(items);
    notifyListeners();
    await _save();
  }

  /// Remove cards given away in a completed trade. Takes from the Up for trade
  /// binder first, then the collection binder, then (only if nothing else is
  /// left) the Showcase. Prefers the exact printing when given.
  void _takeOut(String key, int qty, {String? scryfallId, bool? foil}) {
    var left = qty;
    int rank(CollectionEntry e) {
      var r = switch (e.binder) { Binder.trade => 0, Binder.collection => 10, Binder.showcase => 20 };
      if (scryfallId != null && e.card.id != scryfallId) r += 2;
      if (foil != null && e.foil != foil) r += 1;
      return r;
    }

    final candidates = _entries.where((e) => e.nameKey == key).toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    for (final e in candidates) {
      if (left == 0) break;
      final n = left < e.quantity ? left : e.quantity;
      e.quantity -= n;
      left -= n;
      if (e.quantity == 0) _entries.remove(e);
    }
  }

  /// Apply a completed trade: [out] leaves the collection, [incoming] arrives
  /// in the collection binder.
  Future<void> applyTrade({
    required List<({String key, int qty, String? scryfallId, bool foil})> out,
    required List<({CardPrint card, int qty, bool foil})> incoming,
  }) async {
    for (final o in out) {
      _takeOut(o.key, o.qty, scryfallId: o.scryfallId, foil: o.foil);
    }
    for (final i in incoming) {
      _merge(i.card, i.foil, i.qty, Binder.collection, CardCondition.nm);
    }
    notifyListeners();
    await _save();
  }

  /// Moxfield-compatible CSV (also accepted by most other collection sites).
  String toMoxfieldCsv([Iterable<CollectionEntry>? only]) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('"Count","Name","Edition","Condition","Language","Foil","Collector Number"\n');
    for (final e in (only ?? _entries).toList().reversed) {
      b.writeln([
        esc('${e.quantity}'),
        esc(e.card.name),
        esc(e.card.setCode),
        esc(e.condition.label),
        esc('English'),
        esc(e.foil ? 'foil' : ''),
        esc(e.card.collectorNumber),
      ].join(','));
    }
    return b.toString();
  }

  Future<File> exportCsv([Iterable<CollectionEntry>? only, String name = 'collection']) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    final f = File('${dir.path}/$safe-$stamp.csv');
    await f.writeAsString(toMoxfieldCsv(only));
    return f;
  }
}

/// A folder inside a binder. With a [rule], "Sort now" (and, if [autoSort],
/// every new card) puts matching cards in it.
class CollectionFolder {
  final String name;
  final Binder binder;
  final CollectionQuery? rule;
  final bool autoSort;

  const CollectionFolder({required this.name, required this.binder, this.rule, this.autoSort = false});

  Map<String, dynamic> toJson() => {
        'name': name,
        'binder': binder.id,
        if (rule != null) 'rule': rule!.toJson(),
        if (autoSort) 'auto': true,
      };

  factory CollectionFolder.fromJson(Map<String, dynamic> j) => CollectionFolder(
        name: j['name'] as String,
        binder: Binder.parse(j['binder'] as String?),
        rule: j['rule'] is Map ? CollectionQuery.fromJson((j['rule'] as Map).cast<String, dynamic>()) : null,
        autoSort: j['auto'] as bool? ?? false,
      );
}
