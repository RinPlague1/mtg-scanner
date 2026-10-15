import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  CollectionEntry(
    this.card, {
    this.foil = false,
    this.quantity = 1,
    this.binder = Binder.collection,
    this.condition = CardCondition.nm,
    DateTime? added,
    Set<String>? tags,
  })  : added = added ?? DateTime.now(),
        tags = tags ?? {};

  static String keyFor(CardPrint card, bool foil, Binder binder, CardCondition condition) =>
      '${card.id}|${foil ? 'f' : 'n'}|${binder.id}|${condition.code}';

  String get key => keyFor(card, foil, binder, condition);
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
      };

  factory CollectionEntry.fromJson(Map<String, dynamic> j) => CollectionEntry(
        CardPrint.fromScryfall(j['card'] as Map<String, dynamic>),
        foil: j['foil'] as bool? ?? false,
        quantity: (j['quantity'] ?? j['qty']) as int? ?? 1,
        binder: Binder.parse(j['binder'] as String?),
        condition: CardCondition.parse(j['condition'] as String?),
        added: DateTime.tryParse(j['added'] as String? ?? ''),
        tags: ((j['tags'] as List?) ?? const []).cast<String>().toSet(),
      );
}

String nameKeyOf(CardPrint c) => nameKey(c.name);

/// Local collection persisted as JSON in the app's documents folder. The phone
/// is the source of truth; when signed in, SyncService mirrors it to Supabase.
class CollectionStore extends ChangeNotifier {
  final List<CollectionEntry> _entries = [];
  final JsonFile _file = JsonFile('collection.json');

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
      {bool toFront = true, Set<String> tags = const {}}) {
    final key = CollectionEntry.keyFor(card, foil, binder, condition);
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
              foil: foil, quantity: quantity, binder: binder, condition: condition, tags: {...tags}));
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
      _merge(e.card, e.foil, e.quantity, e.binder, e.condition, tags: e.tags);
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
    final key = CollectionEntry.keyFor(e.card, e.foil, b, c);
    final existing = _entries.where((x) => x.key == key).firstOrNull;
    if (existing != null) {
      existing.quantity += n;
      existing.tags.addAll(e.tags);
    } else {
      final moved = CollectionEntry(e.card,
          foil: e.foil, quantity: n, binder: b, condition: c, added: e.added, tags: {...e.tags});
      _entries.insert(index.clamp(0, _entries.length), moved);
    }
    return true;
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
  String toMoxfieldCsv() {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('"Count","Name","Edition","Condition","Language","Foil","Collector Number"\n');
    for (final e in _entries.reversed) {
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

  Future<File> exportCsv() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/collection-$stamp.csv');
    await f.writeAsString(toMoxfieldCsv());
    return f;
  }
}
