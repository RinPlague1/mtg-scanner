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

/// Pages the app can open on (Collection ⋮ → Start page).
const startPages = <({String id, String label})>[
  (id: 'scan', label: 'Scan'),
  (id: 'collection', label: 'Collection summary'),
  (id: 'collection-list', label: 'Collection (all cards)'),
  (id: 'search', label: 'Search'),
  (id: 'decks', label: 'Decks'),
  (id: 'friends', label: 'Friends'),
  (id: 'trades', label: 'Trades'),
];

class AppSettings extends ChangeNotifier {
  NameMatching nameMatching = NameMatching.offlineList;

  /// Collection screen: grid of card images instead of a list.
  bool collectionGrid = false;
  SortBy sortBy = SortBy.added;
  bool sortDescending = true;

  /// Scanner: show the raw text it reads, for troubleshooting.
  bool showScanDebug = false;

  /// Collection grid: show each card's price on its picture.
  bool showPriceOnCards = false;

  /// Page the app opens on: an id from [startPages].
  String startPage = 'collection';

  /// App colour theme id (an MTG colour combination, e.g. "izzet").
  String theme = 'default';

  /// Collection value at the last price refresh (EUR), for "change since".
  double? lastValueEur;
  DateTime? lastValueAt;

  final JsonFile _file = JsonFile('settings.json');

  Future<void> load() async {
    final data = await _file.open();
    if (data is Map) {
      nameMatching = NameMatching.parse(data['nameMatching'] as String?);
      collectionGrid = data['collectionGrid'] as bool? ?? false;
      sortBy = SortBy.values.firstWhere((s) => s.name == data['sortBy'], orElse: () => SortBy.added);
      sortDescending = data['sortDescending'] as bool? ?? true;
      showScanDebug = data['showScanDebug'] as bool? ?? false;
      showPriceOnCards = data['showPriceOnCards'] as bool? ?? false;
      theme = data['theme'] as String? ?? 'default';
      final start = data['startPage'] as String?;
      startPage = startPages.any((p) => p.id == start) ? start! : 'collection';
      lastValueEur = (data['lastValueEur'] as num?)?.toDouble();
      lastValueAt = DateTime.tryParse(data['lastValueAt'] as String? ?? '');
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write({
        'nameMatching': nameMatching.id,
        'collectionGrid': collectionGrid,
        'sortBy': sortBy.name,
        'sortDescending': sortDescending,
        'showScanDebug': showScanDebug,
        'showPriceOnCards': showPriceOnCards,
        'theme': theme,
        'startPage': startPage,
        if (lastValueEur != null) 'lastValueEur': lastValueEur,
        if (lastValueAt != null) 'lastValueAt': lastValueAt!.toIso8601String(),
      });

  Future<void> setStartPage(String id) async {
    startPage = id;
    notifyListeners();
    await _save();
  }

  Future<void> setTheme(String id) async {
    theme = id;
    notifyListeners();
    await _save();
  }

  Future<void> setShowPriceOnCards(bool v) async {
    showPriceOnCards = v;
    notifyListeners();
    await _save();
  }

  Future<void> setValueSnapshot(double eur) async {
    lastValueEur = eur;
    lastValueAt = DateTime.now();
    notifyListeners();
    await _save();
  }

  Future<void> setShowScanDebug(bool v) async {
    showScanDebug = v;
    notifyListeners();
    await _save();
  }

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
