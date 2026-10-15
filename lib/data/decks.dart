import 'package:flutter/foundation.dart';

import 'json_file.dart';
import 'models.dart';

class DeckCard {
  final String name;
  final int qty;
  final bool commander;

  const DeckCard(this.name, this.qty, {this.commander = false});

  String get key => nameKey(name);

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty, if (commander) 'commander': true};

  factory DeckCard.fromJson(Map<String, dynamic> j) =>
      DeckCard(j['name'] as String, j['qty'] as int? ?? 1, commander: j['commander'] as bool? ?? false);
}

class Deck {
  final String id;
  String name;
  String format;
  DeckStatus status;
  List<DeckCard> cards;
  final DateTime created;

  Deck({
    String? id,
    required this.name,
    this.format = 'commander',
    this.status = DeckStatus.built,
    List<DeckCard>? cards,
    DateTime? created,
  })  : id = id ?? newId(),
        cards = cards ?? [],
        created = created ?? DateTime.now();

  List<DeckCard> get commanders => cards.where((c) => c.commander).toList();
  int get cardCount => cards.fold(0, (s, c) => s + c.qty);

  /// Copies of each card name this deck needs.
  Map<String, int> get needs {
    final m = <String, int>{};
    for (final c in cards) {
      m.update(c.key, (v) => v + c.qty, ifAbsent: () => c.qty);
    }
    return m;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'format': format,
        'status': status.id,
        'created': created.toUtc().toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Untitled deck',
        format: j['format'] as String? ?? 'commander',
        status: DeckStatus.parse(j['status'] as String?),
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        cards: ((j['cards'] as List?) ?? const [])
            .map((c) => DeckCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class DeckStore extends ChangeNotifier {
  final List<Deck> _decks = [];
  final JsonFile _file = JsonFile('decks.json');

  List<Deck> get decks => List.unmodifiable(_decks);
  Deck? byId(String id) => _decks.where((d) => d.id == id).firstOrNull;

  Future<void> load() async {
    final data = await _file.open();
    if (data is List) {
      _decks
        ..clear()
        ..addAll(data.map((d) => Deck.fromJson(d as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write(_decks.map((d) => d.toJson()).toList());

  Future<void> add(Deck d) async {
    _decks.insert(0, d);
    notifyListeners();
    await _save();
  }

  /// Call after changing a deck's fields in place.
  Future<void> changed() async {
    notifyListeners();
    await _save();
  }

  Future<void> remove(Deck d) async {
    _decks.remove(d);
    notifyListeners();
    await _save();
  }

  Future<void> replaceAll(List<Deck> decks) async {
    _decks
      ..clear()
      ..addAll(decks);
    notifyListeners();
    await _save();
  }
}
