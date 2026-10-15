import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/collection.dart';
import 'package:mtg_dark_scanner/data/collection_query.dart';
import 'package:mtg_dark_scanner/data/models.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';

CollectionEntry e(
  String name, {
  List<String> ci = const [],
  String type = 'Artifact',
  String rarity = 'rare',
  String eur = '1.00',
  double cmc = 1,
  bool foil = false,
  Set<String> tags = const {},
  int day = 1,
  String set = 'tst',
  String number = '1',
}) =>
    CollectionEntry(
      CardPrint(
        id: name,
        name: name,
        setCode: set,
        setName: 'Test',
        collectorNumber: number,
        rarity: rarity,
        priceEur: eur,
        // Foil entries are priced from priceEurFoil (CollectionEntry.priceEur).
        priceEurFoil: foil ? eur : null,
        colorIdentity: ci,
        typeLine: type,
        cmc: cmc,
      ),
      foil: foil,
      tags: {...tags},
      added: DateTime(2026, 1, day),
    );

void main() {
  final cards = [
    e('Sol Ring', eur: '1.50', type: 'Artifact', rarity: 'uncommon', day: 3, tags: {'Aang staples'}),
    e('Counterspell', ci: ['U'], type: 'Instant', rarity: 'common', eur: '0.80', cmc: 2, day: 1),
    e('Avatar Aang', ci: ['W', 'U', 'R', 'G'], type: 'Legendary Creature — Human Avatar', rarity: 'mythic', eur: '12', cmc: 4, day: 2, foil: true, tags: {'Aang staples', 'To sell'}),
    e('Island', ci: [], type: 'Basic Land — Island', rarity: 'common', eur: '0.10', cmc: 0, day: 4),
  ];
  List<String> names(CollectionQuery q) => q.apply(cards).map((c) => c.card.name).toList();

  test('default sort is newest first', () {
    expect(names(const CollectionQuery()), ['Island', 'Sol Ring', 'Avatar Aang', 'Counterspell']);
  });

  test('sort by name, price, mana value and rarity', () {
    expect(names(const CollectionQuery(sortBy: SortBy.name, descending: false)),
        ['Avatar Aang', 'Counterspell', 'Island', 'Sol Ring']);
    expect(names(const CollectionQuery(sortBy: SortBy.price)).first, 'Avatar Aang');
    expect(names(const CollectionQuery(sortBy: SortBy.manaValue, descending: false)).first, 'Island');
    expect(names(const CollectionQuery(sortBy: SortBy.rarity)).first, 'Avatar Aang');
  });

  test('ties fall back to name A to Z', () {
    // Counterspell and Island are both common.
    final q = const CollectionQuery(sortBy: SortBy.rarity, descending: false);
    expect(names(q).take(2), ['Counterspell', 'Island']);
  });

  test('colour filters: single colour, multicolour, colourless', () {
    expect(names(const CollectionQuery(colours: {'U'}, sortBy: SortBy.name, descending: false)),
        ['Avatar Aang', 'Counterspell']);
    expect(names(const CollectionQuery(colours: {'M'})), ['Avatar Aang']);
    expect(names(const CollectionQuery(colours: {'C'}, sortBy: SortBy.name, descending: false)),
        ['Island', 'Sol Ring']);
  });

  test('type, rarity, foil, tag and text filters', () {
    expect(names(const CollectionQuery(types: {'Creature'})), ['Avatar Aang']);
    expect(names(const CollectionQuery(types: {'Land', 'Instant'}, sortBy: SortBy.name, descending: false)),
        ['Counterspell', 'Island']);
    expect(names(const CollectionQuery(rarities: {'mythic', 'uncommon'})).toSet(), {'Avatar Aang', 'Sol Ring'});
    expect(names(const CollectionQuery(foil: FoilFilter.foil)), ['Avatar Aang']);
    expect(names(const CollectionQuery(tags: {'To sell'})), ['Avatar Aang']);
    expect(names(const CollectionQuery(tags: {'Aang staples'})).length, 2);
    expect(names(const CollectionQuery(text: 'counter')), ['Counterspell']);
    expect(names(const CollectionQuery(text: 'to sell')), ['Avatar Aang']);
    expect(const CollectionQuery(types: {'Land'}, foil: FoilFilter.foil).filterCount, 2);
  });

  test('cards without details only match when no colour/type filter is set', () {
    final old = CollectionEntry(CardPrint(
      id: 'x', name: 'Old Card', setCode: 'lea', setName: 'Alpha', collectorNumber: '1', rarity: 'rare'));
    expect(const CollectionQuery(colours: {'C'}).matches(old), isFalse);
    expect(const CollectionQuery().matches(old), isTrue);
  });

  test('tags: bulk tag, rename, delete and keep tags when moving binders', () async {
    final store = CollectionStore();
    await store.addAll([e('Sol Ring'), e('Island')]);
    await store.tagAll(store.entries, add: {'To sell'});
    expect(store.allTags, ['To sell']);
    await store.renameTag('To sell', 'Sell pile');
    expect(store.countTagged('Sell pile'), 2);
    await store.moveAll([store.entries.first], binder: Binder.trade);
    expect(store.inBinder(Binder.trade).single.tags, {'Sell pile'});
    await store.deleteTag('Sell pile');
    expect(store.allTags, isEmpty);
    await store.removeAll(store.entries);
    expect(store.isEmpty, isTrue);
  });
}
