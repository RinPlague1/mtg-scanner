import 'package:flutter/foundation.dart';

import 'json_file.dart';
import 'models.dart';

/// A card added to the wishlist by hand. [qty] is how many copies you want to
/// own in total (so owning one already counts toward it).
class WishItem {
  final String name;
  int qty;

  WishItem(this.name, [this.qty = 1]);

  String get key => nameKey(name);

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty};
  factory WishItem.fromJson(Map<String, dynamic> j) => WishItem(j['name'] as String, j['qty'] as int? ?? 1);
}

class WishlistStore extends ChangeNotifier {
  final List<WishItem> _items = [];
  final JsonFile _file = JsonFile('wishlist.json');

  List<WishItem> get items => List.unmodifiable(_items);

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
}
