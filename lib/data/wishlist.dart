import 'package:flutter/foundation.dart';

import 'json_file.dart';
import 'models.dart';
import 'scryfall.dart';

/// How much you want a wishlist card.
enum WishPriority {
  niceToHave(1, 'Nice to have'),
  want(2, 'Want'),
  mustHave(3, 'Must have');

  final int value;
  final String label;
  const WishPriority(this.value, this.label);

  static WishPriority parse(Object? v) =>
      WishPriority.values.firstWhere((p) => p.value == v || p.name == v, orElse: () => WishPriority.want);
}

/// A card added to the wishlist by hand. [qty] is how many copies you want to
/// own in total (so owning one already counts toward it).
class WishItem {
  final String name;
  int qty;
  WishPriority priority;

  /// A specific printing you want, or null for any printing.
  CardPrint? card;

  /// true = foil only, false = non-foil only, null = either.
  bool? foil;

  /// Alert when the price drops to this or below (GBP).
  double? maxGbp;

  /// Last price seen (EUR) for the printing/finish wanted, and when.
  double? lastEur;
  DateTime? checkedAt;

  WishItem(this.name,
      [this.qty = 1, this.priority = WishPriority.want, this.card, this.foil, this.maxGbp, this.lastEur, this.checkedAt]);

  String get key => nameKey(name);

  /// The price that matters for this wish: foil price if foil wanted, else
  /// the cheaper available finish.
  double? priceOf(CardPrint c) {
    final n = double.tryParse(c.priceEur ?? '');
    final f = double.tryParse(c.priceEurFoil ?? '');
    if (foil == true) return f;
    if (foil == false) return n;
    if (n == null) return f;
    if (f == null) return n;
    return n < f ? n : f;
  }

  /// "DFT #102 · foil · Must have" style summary of what's wanted.
  String get details => [
        if (card != null) '${card!.setCode.toUpperCase()} #${card!.collectorNumber}',
        if (foil == true) 'foil',
        if (foil == false) 'non-foil',
        if (priority != WishPriority.want) priority.label,
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        if (priority != WishPriority.want) 'priority': priority.value,
        if (card != null) 'card': card!.toJson(),
        'foil': ?foil,
        'maxGbp': ?maxGbp,
        'lastEur': ?lastEur,
        if (checkedAt != null) 'checkedAt': checkedAt!.toIso8601String(),
      };

  factory WishItem.fromJson(Map<String, dynamic> j) {
    CardPrint? card;
    if (j['card'] is Map) {
      try {
        card = CardPrint.fromScryfall((j['card'] as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    return WishItem(
      j['name'] as String,
      j['qty'] as int? ?? 1,
      WishPriority.parse(j['priority'] ?? 2),
      card,
      j['foil'] as bool?,
      (j['maxGbp'] as num?)?.toDouble(),
      (j['lastEur'] as num?)?.toDouble(),
      DateTime.tryParse(j['checkedAt'] as String? ?? ''),
    );
  }
}

class WishlistStore extends ChangeNotifier {
  final List<WishItem> _items = [];
  final JsonFile _file = JsonFile('wishlist.json');

  List<WishItem> get items => List.unmodifiable(_items);

  bool contains(String name) => _items.any((w) => w.key == nameKey(name));
  WishItem? byName(String name) => _items.where((w) => w.key == nameKey(name)).firstOrNull;

  Future<void> load() async {
    final data = await _file.open();
    if (data is List) {
      _items
        ..clear()
        ..addAll(data.map((w) => WishItem.fromJson(w as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() => _items.map((w) => w.toJson()).toList();

  Future<void> _save() => _file.write(toJson());

  Future<void> add(String name, [int qty = 1]) async {
    final k = nameKey(name);
    final existing = _items.where((w) => w.key == k).firstOrNull;
    if (existing != null) {
      existing.qty += qty;
    } else {
      _items.insert(0, WishItem(name, qty));
    }
    notifyListeners();
    await _save();
  }

  /// Add or update a full wish (printing, finish, priority, price alert).
  Future<void> put(WishItem item) async {
    final i = _items.indexWhere((w) => w.key == item.key);
    if (i >= 0) {
      _items[i] = item;
    } else {
      _items.insert(0, item);
    }
    notifyListeners();
    await _save();
  }

  /// Call after changing an item's fields in place.
  Future<void> changed() async {
    notifyListeners();
    await _save();
  }

  Future<void> remove(WishItem w) async {
    _items.remove(w);
    notifyListeners();
    await _save();
  }

  Future<void> replaceAll(List<WishItem> items) async {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
    await _save();
  }

  /// Fetch current prices (offline card data first, otherwise Scryfall).
  Future<void> checkPrices(ScryfallClient scryfall) async {
    if (_items.isEmpty) return;
    final ids = <Map<String, String>>[
      for (final w in _items) w.card != null ? {'id': w.card!.id} : {'name': w.name},
    ];
    final found = await scryfall.collection(ids);
    final byId = {for (final c in found) c.id: c};
    final byName = <String, CardPrint>{};
    for (final c in found) {
      byName.putIfAbsent(nameKey(c.name), () => c);
    }
    final now = DateTime.now();
    for (final w in _items) {
      final c = w.card != null ? byId[w.card!.id] : byName[w.key];
      if (c == null) continue;
      if (w.card != null) w.card = c;
      w.lastEur = w.priceOf(c);
      w.checkedAt = now;
    }
    notifyListeners();
    await _save();
  }

  /// Wishes whose price is at or under their alert price.
  List<WishItem> alerts(double Function(double eur) toGbp) => [
        for (final w in _items)
          if (w.maxGbp != null && w.lastEur != null && toGbp(w.lastEur!) <= w.maxGbp! + 0.0001) w,
      ];
}
