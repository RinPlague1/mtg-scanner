import 'package:flutter/foundation.dart';

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
  final JsonFile _file = JsonFile('settings.json');

  Future<void> load() async {
    final data = await _file.open();
    if (data is Map) {
      nameMatching = NameMatching.parse(data['nameMatching'] as String?);
    }
    notifyListeners();
  }

  Future<void> setNameMatching(NameMatching m) async {
    if (m == nameMatching) return;
    nameMatching = m;
    notifyListeners();
    await _file.write({'nameMatching': m.id});
  }
}
