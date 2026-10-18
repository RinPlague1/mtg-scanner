import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/collection.dart';
import 'package:mtg_dark_scanner/data/decks.dart';
import 'package:mtg_dark_scanner/data/models.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';
import 'package:mtg_dark_scanner/data/trade_logic.dart';
import 'package:mtg_dark_scanner/data/wishlist.dart';

CardPrint card(String id, String name, {String eur = '1.00'}) => CardPrint(
      id: id,
      name: name,
      setCode: 'tst',
      setName: 'Test',
      collectorNumber: '1',
      rarity: 'rare',
      priceEur: eur,
    );

CollectionEntry entry(String id, String name, int qty, Binder b) =>
    CollectionEntry(card(id, name), quantity: qty, binder: b);

int total(List<TradeCard> cards, String key, {bool? listed}) =>
    cards.where((c) => c.key == key && (listed == null || c.listed == listed)).fold(0, (n, c) => n + c.qty);

void main() {
  group('spares', () {
    test('collection copies above Built deck needs are spare; Showcase never is', () {
      final entries = [
        entry('a', 'Sol Ring', 3, Binder.collection),
        entry('b', 'Rhystic Study', 1, Binder.showcase),
        entry('c', 'Counterspell', 2, Binder.collection),
      ];
      final decks = [
        Deck(name: 'Tam', cards: [const DeckCard('Sol Ring', 1), const DeckCard('Counterspell', 1)]),
      ];
      final spares = computeSpares(entries, decks);
      expect(total(spares, 'sol ring'), 2);
      expect(total(spares, 'counterspell'), 1);
      expect(total(spares, 'rhystic study'), 0);
    });

    test('the deck takes priority over the Up for trade binder', () {
      final entries = [entry('a', 'Sol Ring', 1, Binder.trade)];
      final built = [Deck(name: 'Aang', cards: [const DeckCard('Sol Ring', 1)])];
      expect(computeSpares(entries, built), isEmpty);

      // Brewing and Retired decks reserve nothing.
      final brewing = [Deck(name: 'Aang', status: DeckStatus.brewing, cards: [const DeckCard('Sol Ring', 1)])];
      final retired = [Deck(name: 'Aang', status: DeckStatus.retired, cards: [const DeckCard('Sol Ring', 1)])];
      expect(total(computeSpares(entries, brewing), 'sol ring', listed: true), 1);
      expect(total(computeSpares(entries, retired), 'sol ring', listed: true), 1);
    });

    test('decks use collection copies before listed ones', () {
      final entries = [
        entry('a', 'Sol Ring', 1, Binder.collection),
        entry('b', 'Sol Ring', 1, Binder.trade),
      ];
      final decks = [Deck(name: 'Aang', cards: [const DeckCard('Sol Ring', 1)])];
      final spares = computeSpares(entries, decks);
      expect(total(spares, 'sol ring', listed: true), 1);
      expect(total(spares, 'sol ring', listed: false), 0);
    });

    test('copies promised in open trades are held back', () {
      final entries = [
        entry('a', 'Sol Ring', 2, Binder.trade),
        entry('b', 'Sol Ring', 1, Binder.collection),
      ];
      final spares = computeSpares(entries, const [], reserved: {'sol ring': 2});
      expect(total(spares, 'sol ring', listed: true), 0);
      expect(total(spares, 'sol ring', listed: false), 1);
    });
  });

  group('wants', () {
    test('Built gaps outrank Brewing gaps and the wishlist; Retired adds nothing', () {
      final entries = [entry('a', 'Sol Ring', 1, Binder.collection)];
      final decks = [
        Deck(name: 'Aang', cards: [const DeckCard('Sol Ring', 1), const DeckCard('Cyclonic Rift', 1)]),
        Deck(name: 'Sharks', status: DeckStatus.brewing, cards: [const DeckCard('Rhystic Study', 1)]),
        Deck(name: 'Old', status: DeckStatus.retired, cards: [const DeckCard('Mana Crypt', 1)]),
      ];
      final wants = computeWants(entries, decks, [WishItem('Smothering Tithe')]);
      expect(wants.map((w) => w.name), ['Cyclonic Rift', 'Rhystic Study', 'Smothering Tithe']);
      expect(wants.first.priority, 3);
      expect(wants.first.reason, 'Built: Aang');
      expect(wants[1].priority, 2);
      expect(wants[2].reason, 'Wishlist');
    });

    test('owning enough copies removes the want', () {
      final entries = [entry('a', 'Sol Ring', 2, Binder.showcase)];
      final decks = [
        Deck(name: 'A', cards: [const DeckCard('Sol Ring', 1)]),
        Deck(name: 'B', status: DeckStatus.brewing, cards: [const DeckCard('Sol Ring', 1)]),
      ];
      expect(computeWants(entries, decks, const []), isEmpty);
      final more = [...decks, Deck(name: 'C', cards: [const DeckCard('Sol Ring', 1)])];
      expect(computeWants(entries, more, const []).single.qty, 1);
    });
  });

  group('suggestions', () {
    const myWants = [WantCard(key: 'rhystic study', name: 'Rhystic Study', qty: 1, priority: 3, reason: 'Built: Tam')];
    const mySpares = [TradeCard(key: 'sol ring', name: 'Sol Ring', qty: 2, priceEur: 1)];
    const friendWants = [WantCard(key: 'sol ring', name: 'Sol Ring', qty: 1, priority: 2, reason: 'Wishlist')];
    const friendSpares = [
      TradeCard(key: 'rhystic study', name: 'Rhystic Study', qty: 1, priceEur: 30, scryfallId: 'cheap'),
      TradeCard(key: 'rhystic study', name: 'Rhystic Study', qty: 1, priceEur: 40, listed: true, scryfallId: 'listed'),
      TradeCard(key: 'island', name: 'Island', qty: 10),
    ];

    test('two-way match, listed copies first, quantities capped', () {
      final s = suggestTrade(
        friendId: 'f',
        friendName: 'Sam',
        myWants: myWants,
        mySpares: mySpares,
        friendWants: friendWants,
        friendSpares: friendSpares,
      )!;
      expect(s.theyGive.single.scryfallId, 'listed');
      expect(s.youGive.single.qty, 1);
      expect(s.isSwap, isTrue);
      // 3 (built gap) + 1 (listed) + 2 (wishlist) + 5 (two-way bonus)
      expect(s.score, 11);
      expect(s.theyGiveEur, 40);
    });

    test('no overlap gives no suggestion', () {
      expect(
        suggestTrade(
          friendId: 'f',
          friendName: 'Sam',
          myWants: const [],
          mySpares: const [],
          friendWants: const [],
          friendSpares: friendSpares,
        ),
        isNull,
      );
    });

    test('TradeCard JSON round trip', () {
      final c = TradeCard.fromJson(friendSpares[1].toJson());
      expect(c.listed, isTrue);
      expect(c.priceEur, 40);
      expect(c.scryfallId, 'listed');
    });
  });

  group('collection', () {
    test('moving copies between binders splits and merges entries', () async {
      final store = CollectionStore();
      await store.add(card('a', 'Sol Ring'), quantity: 3);
      final e = store.entries.single;
      await store.move(e, 2, binder: Binder.trade);
      expect(store.countIn(Binder.collection), 1);
      expect(store.countIn(Binder.trade), 2);
      await store.move(store.inBinder(Binder.collection).single, 1, binder: Binder.trade);
      expect(store.entries.single.binder, Binder.trade);
      expect(store.entries.single.quantity, 3);
    });

    test('completed trades take from Up for trade first and add received cards', () async {
      final store = CollectionStore();
      await store.add(card('a', 'Sol Ring'), quantity: 1, binder: Binder.showcase);
      await store.add(card('a', 'Sol Ring'), quantity: 1, binder: Binder.trade);
      await store.applyTrade(
        out: [(key: 'sol ring', qty: 1, scryfallId: 'a', foil: false)],
        incoming: [(card: card('z', 'Rhystic Study'), qty: 1, foil: false)],
      );
      expect(store.countIn(Binder.trade), 0);
      expect(store.countIn(Binder.showcase), 1);
      expect(store.ownedCount('rhystic study'), 1);
    });

    test('changing printing or finish keeps binder and tags, and merges', () async {
      final store = CollectionStore();
      await store.add(card('a', 'Sol Ring'), quantity: 2, binder: Binder.trade);
      await store.add(card('b', 'Sol Ring'), quantity: 1, binder: Binder.trade);
      store.entries.firstWhere((e) => e.card.id == 'a').tags.add('cube');
      final a = store.entries.firstWhere((e) => e.card.id == 'a');
      final merged = await store.changePrinting(a, card('b', 'Sol Ring'));
      expect(store.entries.length, 1);
      expect(merged.card.id, 'b');
      expect(merged.quantity, 3);
      expect(merged.binder, Binder.trade);
      expect(merged.tags, contains('cube'));
      final foiled = await store.changePrinting(merged, merged.card, foil: true);
      expect(store.entries.single.foil, isTrue);
      expect(foiled.quantity, 3);
    });

    test('old saved entries without binder or condition load as collection / NM', () {
      final e = CollectionEntry.fromJson({
        'card': card('a', 'Sol Ring').toJson(),
        'foil': false,
        'quantity': 2,
        'added': '2026-01-01T00:00:00.000',
      });
      expect(e.binder, Binder.collection);
      expect(e.condition, CardCondition.nm);
    });
  });
}
