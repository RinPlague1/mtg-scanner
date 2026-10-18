import 'package:flutter/foundation.dart';

import 'json_file.dart';
import 'models.dart';
import 'scryfall.dart';

class DeckCard {
  final String name;
  final int qty;
  final bool commander;

  /// Card details (type, mana cost, image, price) for showing the deck.
  /// Any printing satisfies the slot; this is just the one shown. Null until
  /// fetched for imported lists.
  final CardPrint? card;

  const DeckCard(this.name, this.qty, {this.commander = false, this.card});

  String get key => nameKey(name);

  DeckCard copyWith({int? qty, bool? commander, CardPrint? card}) =>
      DeckCard(name, qty ?? this.qty, commander: commander ?? this.commander, card: card ?? this.card);

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        if (commander) 'commander': true,
        if (card != null) 'card': card!.toJson(),
      };

  factory DeckCard.fromJson(Map<String, dynamic> j) {
    CardPrint? card;
    final c = j['card'];
    if (c is Map<String, dynamic>) {
      try {
        card = CardPrint.fromScryfall(c);
      } catch (_) {}
    }
    return DeckCard(j['name'] as String, j['qty'] as int? ?? 1,
        commander: j['commander'] as bool? ?? false, card: card);
  }
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

  DeckCard? byKey(String key) => cards.where((c) => c.key == key).firstOrNull;

  /// Add [qty] copies of a card (merging with the same name). Returns the new count.
  int addCard(CardPrint card, {int qty = 1}) {
    final key = nameKey(card.name);
    final i = cards.indexWhere((c) => c.key == key);
    if (i >= 0) {
      final c = cards[i];
      cards[i] = c.copyWith(qty: c.qty + qty, card: c.card ?? card);
      return cards[i].qty;
    }
    cards = [...cards, DeckCard(card.name, qty, card: card)];
    return qty;
  }

  /// Set a card's count; 0 or less removes it.
  void setQty(String key, int qty) {
    if (qty <= 0) {
      cards = cards.where((c) => c.key != key).toList();
    } else {
      cards = [for (final c in cards) c.key == key ? c.copyWith(qty: qty) : c];
    }
  }

  void setCommander(String key, bool commander) {
    cards = [for (final c in cards) c.key == key ? c.copyWith(commander: commander) : c];
  }

  /// Show a different printing for a card (doesn't change what you need).
  void setPrinting(String key, CardPrint card) {
    cards = [for (final c in cards) c.key == key ? c.copyWith(card: card) : c];
  }

  /// Colour identity of the commander(s), or null if unknown / no commander.
  Set<String>? get commanderColours {
    final cs = commanders;
    if (cs.isEmpty || cs.any((c) => c.card == null)) return null;
    return {for (final c in cs) ...c.card!.colorIdentity};
  }

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

  /// Fetch card details for any cards that don't have them yet (imported
  /// lists only store names). Returns how many are still without details.
  Future<int> fillDetails(Deck d, ScryfallClient scryfall) async {
    final missing = d.cards.where((c) => c.card == null).toList();
    if (missing.isEmpty) return 0;
    final found = await scryfall.collection([for (final c in missing) {'name': c.name}]);
    final byKey = <String, CardPrint>{};
    for (final p in found) {
      byKey[nameKey(p.name)] = p;
    }
    d.cards = [for (final c in d.cards) c.card == null && byKey[c.key] != null ? c.copyWith(card: byKey[c.key]) : c];
    await changed();
    return d.cards.where((c) => c.card == null).length;
  }

  Future<void> replaceAll(List<Deck> decks) async {
    _decks
      ..clear()
      ..addAll(decks);
    notifyListeners();
    await _save();
  }
}
