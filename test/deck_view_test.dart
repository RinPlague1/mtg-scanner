import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/deck_view.dart';
import 'package:mtg_dark_scanner/data/decks.dart';
import 'package:mtg_dark_scanner/data/importer.dart';
import 'package:mtg_dark_scanner/data/list_parser.dart';
import 'package:mtg_dark_scanner/data/models.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';

CardPrint p(String name, String type, {double cmc = 0, String cost = '', String eur = '1.00', List<String> ci = const []}) =>
    CardPrint(
      id: name,
      name: name,
      setCode: 'tst',
      setName: 'Test',
      collectorNumber: '1',
      rarity: 'rare',
      priceEur: eur,
      typeLine: type,
      cmc: cmc,
      manaCost: cost,
      colorIdentity: ci,
    );

Deck sample() => Deck(name: 'Sharks', cards: [
      DeckCard('Captain Howler', 1,
          commander: true,
          card: p('Captain Howler', 'Legendary Creature — Shark Pirate', cmc: 4, cost: '{2}{U}{R}', ci: ['U', 'R'])),
      DeckCard('Sol Ring', 1, card: p('Sol Ring', 'Artifact', cmc: 1, cost: '{1}')),
      DeckCard('Counterspell', 1, card: p('Counterspell', 'Instant', cmc: 2, cost: '{U}{U}')),
      DeckCard('Steam Vents', 1, card: p('Steam Vents', 'Land — Island Mountain')),
      DeckCard('Island', 10, card: p('Island', 'Basic Land — Island', eur: '0.10')),
      DeckCard('Ornithopter', 1, card: p('Ornithopter', 'Artifact Creature — Thopter', cmc: 0, cost: '{0}')),
      DeckCard('Boros Charm', 1, card: p('Boros Charm', 'Instant', cmc: 2, cost: '{R}{W}')),
      DeckCard('Kitchen Finks', 1, card: p('Kitchen Finks', 'Creature', cmc: 3, cost: '{1}{G/W}{G/W}')),
      const DeckCard('Mystery Card', 1),
    ]);

void main() {
  test('cards are grouped by type with the commander first', () {
    final groups = groupDeck(sample());
    expect(groups.map((g) => g.$1).toList(), [
      DeckGroup.commander,
      DeckGroup.creature,
      DeckGroup.instant,
      DeckGroup.artifact,
      DeckGroup.land,
      DeckGroup.other,
    ]);
    // Artifact creature counts as a creature; sorted by mana value.
    expect(groups[1].$2.map((c) => c.name), ['Ornithopter', 'Kitchen Finks']);
  });

  test('stats: curve skips lands, pips count hybrid both ways, value and unknowns', () {
    final s = deckStats(sample());
    expect(s.cards, 18);
    expect(s.lands, 11);
    expect(s.unknown, 1);
    expect(s.curve.sublist(0, 5), [1, 1, 2, 1, 1]);
    expect(s.pips, {'W': 3, 'U': 3, 'B': 0, 'R': 2, 'G': 2});
    expect(s.valueEur, closeTo(8.0, 0.001)); // 7 priced cards at 1.00 + 10 Islands at 0.10
    expect(s.averageMv, closeTo((4 + 1 + 2 + 0 + 2 + 3) / 6, 0.001));
  });

  test('editing: add merges, quantity 0 removes, commander toggles', () {
    final d = sample();
    expect(d.addCard(p('Island', 'Basic Land — Island')), 11);
    expect(d.addCard(p('Brainstorm', 'Instant', cmc: 1, cost: '{U}')), 1);
    d.setQty(nameKey('Sol Ring'), 0);
    expect(d.byKey('sol ring'), isNull);
    d.setCommander('counterspell', true);
    expect(d.commanders.length, 2);
    expect(d.commanderColours, {'U', 'R'});
  });

  test('exported text imports back to the same deck', () {
    final d = sample();
    final text = deckToText(d);
    expect(text, startsWith('Commander\n1 Captain Howler\n\nDeck\n'));
    final back = deckFromLines('x', parseCardList(text).lines, DeckStatus.built);
    expect(back.cardCount, d.cardCount);
    expect(back.commanders.single.name, 'Captain Howler');
  });

  test('proxies fill the slot: not needed from the collection, kept when saved', () {
    final d = Deck(name: 'P', cards: [const DeckCard('Mana Crypt', 1), const DeckCard('Island', 10)]);
    d.setProxies('mana crypt', 1);
    d.setProxies('island', 4);
    expect(d.needs, {'island': 6});
    d.setQty('island', 3); // fewer copies than proxies: proxies shrink too
    expect(d.byKey('island')!.proxies, 3);
    expect(d.needs, isEmpty);
    d.shared = true;
    final again = Deck.fromJson(d.toJson());
    expect(again.shared, isTrue);
    expect(again.byKey('mana crypt')!.proxies, 1);
  });

  test('saved deck cards keep their details', () {
    final c = sample().cards.first;
    final again = DeckCard.fromJson(c.toJson());
    expect(again.card?.manaCost, '{2}{U}{R}');
    expect(again.card?.typeLine, startsWith('Legendary Creature'));
    expect(again.commander, isTrue);
  });
}
