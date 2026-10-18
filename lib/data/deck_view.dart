/// Grouping, stats and text export for a deck. Pure Dart, unit-tested
/// (test/deck_view_test.dart).
library;

import 'decks.dart';

enum DeckGroup {
  commander('Commander'),
  creature('Creatures'),
  planeswalker('Planeswalkers'),
  battle('Battles'),
  instant('Instants'),
  sorcery('Sorceries'),
  artifact('Artifacts'),
  enchantment('Enchantments'),
  land('Lands'),
  other('Other');

  final String label;
  const DeckGroup(this.label);
}

/// Which heading a card sits under. Uses the front face; a creature that is
/// also an artifact counts as a creature, an artifact land as a land.
DeckGroup groupFor(DeckCard c) {
  if (c.commander) return DeckGroup.commander;
  final full = c.card?.typeLine.toLowerCase() ?? '';
  final t = full.split('//').first;
  if (t.isEmpty) return DeckGroup.other;
  if (t.contains('creature')) return DeckGroup.creature;
  if (t.contains('planeswalker')) return DeckGroup.planeswalker;
  if (t.contains('battle')) return DeckGroup.battle;
  if (t.contains('land')) return DeckGroup.land;
  if (t.contains('instant')) return DeckGroup.instant;
  if (t.contains('sorcery')) return DeckGroup.sorcery;
  if (t.contains('artifact')) return DeckGroup.artifact;
  if (t.contains('enchantment')) return DeckGroup.enchantment;
  return DeckGroup.other;
}

/// Cards under each heading, in heading order, sorted by mana value then name.
List<(DeckGroup, List<DeckCard>)> groupDeck(Deck d) {
  final map = <DeckGroup, List<DeckCard>>{};
  for (final c in d.cards) {
    map.putIfAbsent(groupFor(c), () => []).add(c);
  }
  return [
    for (final g in DeckGroup.values)
      if (map[g] != null)
        (
          g,
          map[g]!
            ..sort((a, b) {
              final m = (a.card?.cmc ?? 99).compareTo(b.card?.cmc ?? 99);
              return m != 0 ? m : a.name.compareTo(b.name);
            })
        ),
  ];
}

class DeckStats {
  /// Non-land cards by mana value: index 0–6, and 7 = "7 or more".
  final List<int> curve;

  /// Coloured mana symbols in costs (W U B R G), hybrid counting for both.
  final Map<String, int> pips;
  final Map<DeckGroup, int> groups;
  final int lands;
  final int cards;

  /// Average mana value of non-land cards with known costs.
  final double averageMv;

  /// Cardmarket value of the printings shown (non-foil), in EUR.
  final double valueEur;

  /// Cards whose details haven't loaded yet.
  final int unknown;

  const DeckStats({
    required this.curve,
    required this.pips,
    required this.groups,
    required this.lands,
    required this.cards,
    required this.averageMv,
    required this.valueEur,
    required this.unknown,
  });
}

DeckStats deckStats(Deck d) {
  final curve = List<int>.filled(8, 0);
  final pips = {for (final c in 'WUBRG'.split('')) c: 0};
  final groups = <DeckGroup, int>{};
  var lands = 0, cards = 0, unknown = 0, mvCount = 0;
  var mvTotal = 0.0, value = 0.0;
  for (final c in d.cards) {
    cards += c.qty;
    final g = groupFor(c);
    groups.update(g, (v) => v + c.qty, ifAbsent: () => c.qty);
    final p = c.card;
    if (p == null) {
      unknown += c.qty;
      continue;
    }
    value += (double.tryParse(p.priceEur ?? '') ?? 0) * c.qty;
    final isLand = p.typeLine.toLowerCase().split('//').first.contains('land') &&
        !p.typeLine.toLowerCase().contains('creature');
    if (isLand) {
      lands += c.qty;
      continue;
    }
    final mv = p.cmc;
    if (mv != null) {
      curve[mv.round().clamp(0, 7)] += c.qty;
      mvTotal += mv * c.qty;
      mvCount += c.qty;
    }
    for (final m in RegExp(r'\{([^}]+)\}').allMatches(p.manaCost)) {
      for (final ch in m.group(1)!.split('/')) {
        if (pips.containsKey(ch)) pips[ch] = pips[ch]! + c.qty;
      }
    }
  }
  return DeckStats(
    curve: curve,
    pips: pips,
    groups: groups,
    lands: lands,
    cards: cards,
    averageMv: mvCount == 0 ? 0 : mvTotal / mvCount,
    valueEur: value,
    unknown: unknown,
  );
}

/// Decklist text that Moxfield, Archidekt and this app's importer read:
/// a "Commander" section, then "Deck".
String deckToText(Deck d) {
  final b = StringBuffer();
  final commanders = d.cards.where((c) => c.commander).toList();
  final rest = d.cards.where((c) => !c.commander).toList()..sort((a, b) => a.name.compareTo(b.name));
  if (commanders.isNotEmpty) {
    b.writeln('Commander');
    for (final c in commanders) {
      b.writeln('${c.qty} ${c.name}');
    }
    b.writeln();
    b.writeln('Deck');
  }
  for (final c in rest) {
    b.writeln('${c.qty} ${c.name}');
  }
  return b.toString().trimRight();
}
