import 'package:flutter/foundation.dart';

import 'collection_query.dart';
import 'json_file.dart';

/// How the scanner turns OCR text into a card name.
enum NameMatching {
  /// Download Scryfall's card-name list once (about 1 MB, refreshed weekly)
  /// and match on the phone. Faster and more forgiving of OCR mistakes.
  offlineList('offline', 'Download card names'),

  /// Nothing downloaded: each scan's text goes to Scryfall's fuzzy search.
  /// Needs a connection for every scan.
  scryfallOnline('online', 'Use Scryfall online');

  final String id;
  final String label;
  const NameMatching(this.id, this.label);

  static NameMatching parse(String? s) =>
      NameMatching.values.firstWhere((m) => m.id == s, orElse: () => NameMatching.offlineList);
}

class AppSettings extends ChangeNotifier {
  NameMatching nameMatching = NameMatching.offlineList;

  /// Collection screen: grid of card images instead of a list.
  bool collectionGrid = false;
  SortBy sortBy = SortBy.added;
  bool sortDescending = true;

  final JsonFile _file = JsonFile('settings.json');

  Future<void> load() async {
    final data = await _file.open();
    if (data is Map) {
      nameMatching = NameMatching.parse(data['nameMatching'] as String?);
      collectionGrid = data['collectionGrid'] as bool? ?? false;
      sortBy = SortBy.values.firstWhere((s) => s.name == data['sortBy'], orElse: () => SortBy.added);
      sortDescending = data['sortDescending'] as bool? ?? true;
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write({
        'nameMatching': nameMatching.id,
        'collectionGrid': collectionGrid,
        'sortBy': sortBy.name,
        'sortDescending': sortDescending,
      });

  Future<void> setNameMatching(NameMatching m) async {
    if (m == nameMatching) return;
    nameMatching = m;
    notifyListeners();
    await _save();
  }

  Future<void> setCollectionView({bool? grid, SortBy? sortBy, bool? descending}) async {
    if (grid != null) collectionGrid = grid;
    if (sortBy != null) this.sortBy = sortBy;
    if (descending != null) sortDescending = descending;
    notifyListeners();
    await _save();
  }
}
