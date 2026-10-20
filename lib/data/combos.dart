/// Combos for a deck from Commander Spellbook (commanderspellbook.com).
/// Parsing is pure Dart and unit-tested (test/combos_test.dart).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'decks.dart';
import 'models.dart';

class Combo {
  final String id;
  final List<String> cards;
  final List<String> results;
  final String description;

  /// Cards in the combo you don't have in the deck (for "almost" combos).
  final List<String> missing;

  const Combo({
    required this.id,
    required this.cards,
    required this.results,
    this.description = '',
    this.missing = const [],
  });

  String get url => 'https://commanderspellbook.com/combo/$id/';
}

class DeckCombos {
  final List<Combo> included;
  final List<Combo> almost;
  const DeckCombos(this.included, this.almost);
}

List<String> _names(Object? list, String inner) {
  final out = <String>[];
  for (final x in (list as List?) ?? const []) {
    if (x is String) {
      out.add(x);
    } else if (x is Map) {
      final v = x[inner];
      if (v is Map && v['name'] is String) {
        out.add(v['name'] as String);
      } else if (v is String) {
        out.add(v);
      } else if (x['name'] is String) {
        out.add(x['name'] as String);
      }
    }
  }
  return out;
}

Combo parseCombo(Map<String, dynamic> j, Set<String> deckKeys) {
  final cards = _names(j['uses'], 'card');
  final results = _names(j['produces'], 'feature');
  return Combo(
    id: '${j['id'] ?? ''}',
    cards: cards,
    results: results,
    description: (j['description'] as String? ?? '').trim(),
    missing: [for (final c in cards) if (!deckKeys.contains(nameKey(c))) c],
  );
}

/// Reads Commander Spellbook's find-my-combos reply.
DeckCombos parseFindMyCombos(Map<String, dynamic> j, Set<String> deckKeys) {
  final r = (j['results'] as Map?) ?? j;
  List<Combo> list(String k) => [
        for (final x in (r[k] as List?) ?? const [])
          if (x is Map) parseCombo(x.cast<String, dynamic>(), deckKeys),
      ];
  final almost = [...list('almostIncluded'), ...list('almostIncludedByAddingColors')]
      .where((c) => c.missing.length == 1)
      .toList();
  return DeckCombos(list('included'), almost);
}

class CombosClient {
  final http.Client _http;
  final _cache = <String, DeckCombos>{};
  CombosClient([http.Client? client]) : _http = client ?? http.Client();

  /// Combos fully in [deck], and ones a single card away.
  Future<DeckCombos> forDeck(Deck deck) async {
    final commanders = [for (final c in deck.cards) if (c.commander) {'card': c.name, 'quantity': c.qty}];
    final main = [for (final c in deck.cards) if (!c.commander) {'card': c.name, 'quantity': c.qty}];
    final body = jsonEncode({'commanders': commanders, 'main': main});
    final cached = _cache[body];
    if (cached != null) return cached;
    final res = await _http
        .post(
          Uri.parse('https://backend.commanderspellbook.com/find-my-combos'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'MTGBinder/0.2'},
          body: body,
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw Exception('Commander Spellbook ${res.statusCode}');
    final keys = {for (final c in deck.cards) c.key};
    final out = parseFindMyCombos(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, keys);
    _cache[body] = out;
    return out;
  }
}
