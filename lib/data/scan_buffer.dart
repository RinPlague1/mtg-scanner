import 'package:flutter/foundation.dart';

import 'collection.dart';
import 'json_file.dart';
import 'models.dart';
import 'scryfall.dart';

/// One scanned card waiting for review.
class BufferItem {
  final String id;
  CardPrint card;
  bool foil;
  int quantity;
  CardCondition condition;
  Binder binder;

  /// False when the printing was guessed from the name only.
  bool exactPrinting;
  final DateTime scanned;

  BufferItem({
    String? id,
    required this.card,
    this.foil = false,
    this.quantity = 1,
    this.condition = CardCondition.nm,
    this.binder = Binder.collection,
    this.exactPrinting = true,
    DateTime? scanned,
  })  : id = id ?? newId(),
        scanned = scanned ?? DateTime.now();

  double? get priceEur => double.tryParse((foil ? card.priceEurFoil : card.priceEur) ?? '');

  Map<String, dynamic> toJson() => {
        'id': id,
        'card': card.toJson(),
        'foil': foil,
        'quantity': quantity,
        'condition': condition.code,
        'binder': binder.id,
        'exact': exactPrinting,
        'scanned': scanned.toIso8601String(),
      };

  factory BufferItem.fromJson(Map<String, dynamic> j) => BufferItem(
        id: j['id'] as String?,
        card: CardPrint.fromScryfall(j['card'] as Map<String, dynamic>),
        foil: j['foil'] as bool? ?? false,
        quantity: j['quantity'] as int? ?? 1,
        condition: CardCondition.parse(j['condition'] as String?),
        binder: Binder.parse(j['binder'] as String?),
        exactPrinting: j['exact'] as bool? ?? true,
        scanned: DateTime.tryParse(j['scanned'] as String? ?? ''),
      );
}

/// Cards scanned but not yet added to the collection. Saved on the phone, so a
/// half-reviewed stack survives closing the app.
class ScanBuffer extends ChangeNotifier {
  final List<BufferItem> _items = [];
  final JsonFile _file = JsonFile('scan_buffer.json');

  List<BufferItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (n, i) => n + i.quantity);
  bool get isEmpty => _items.isEmpty;
  double get totalEur => _items.fold(0.0, (s, i) => s + (i.priceEur ?? 0) * i.quantity);

  Future<void> load() async {
    final data = await _file.open();
    if (data is List) {
      _items
        ..clear()
        ..addAll(data.map((e) => BufferItem.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write(_items.map((i) => i.toJson()).toList());

  /// Add a scan. Scanning the same printing again (same foil, binder and
  /// condition) bumps its quantity instead of adding a new row.
  Future<BufferItem> add(
    CardPrint card, {
    bool foil = false,
    Binder binder = Binder.collection,
    bool exactPrinting = true,
  }) async {
    final same = _items
        .where((i) =>
            i.card.id == card.id && i.foil == foil && i.binder == binder && i.condition == CardCondition.nm)
        .firstOrNull;
    final BufferItem item;
    if (same != null) {
      same.quantity++;
      _items
        ..remove(same)
        ..insert(0, same);
      item = same;
    } else {
      item = BufferItem(card: card, foil: foil, binder: binder, exactPrinting: exactPrinting);
      _items.insert(0, item);
    }
    notifyListeners();
    await _save();
    return item;
  }

  /// Undo one scan of [item] (from the "Added" snack bar).
  Future<void> undo(BufferItem item) async {
    if (!_items.contains(item)) return;
    if (item.quantity > 1) {
      item.quantity--;
    } else {
      _items.remove(item);
    }
    notifyListeners();
    await _save();
  }

  /// Call after changing an item's fields.
  Future<void> changed() async {
    notifyListeners();
    await _save();
  }

  Future<void> remove(BufferItem item) async {
    _items.remove(item);
    notifyListeners();
    await _save();
  }

  Future<void> setAll({Binder? binder, CardCondition? condition, bool? foil}) async {
    for (final i in _items) {
      if (binder != null) i.binder = binder;
      if (condition != null) i.condition = condition;
      if (foil != null) i.foil = foil;
    }
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }

  /// Move [items] (default: everything) into the collection. Returns the
  /// number of cards added.
  Future<int> commit(CollectionStore collection, [Iterable<BufferItem>? items]) async {
    final chosen = (items ?? _items).toList();
    if (chosen.isEmpty) return 0;
    await collection.addAll(chosen.map((i) => CollectionEntry(
          i.card,
          foil: i.foil,
          quantity: i.quantity,
          binder: i.binder,
          condition: i.condition,
        )));
    final added = chosen.fold(0, (n, i) => n + i.quantity);
    _items.removeWhere(chosen.contains);
    notifyListeners();
    await _save();
    return added;
  }
}
