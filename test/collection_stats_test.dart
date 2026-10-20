import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/collection.dart';
import 'package:mtg_dark_scanner/data/collection_query.dart';
import 'package:mtg_dark_scanner/data/collection_stats.dart';
import 'package:mtg_dark_scanner/data/models.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';
import 'package:mtg_dark_scanner/data/wishlist.dart';

CardPrint card(String id, String name, {String set = 'dft', String n = '1', String eur = '1.00', String type = 'Creature', List<String> ci = const ['U']}) =>
    CardPrint(
      id: id,
      name: name,
      setCode: set,
      setName: set.toUpperCase(),
      collectorNumber: n,
      rarity: 'rare',
      priceEur: eur,
      typeLine: type,
      colorIdentity: ci,
    );

void main() {
  test('duplicates skip basics and respect the keep count', () {
    final entries = [
      CollectionEntry(card('a', 'Sol Ring'), quantity: 3),
      CollectionEntry(card('b', 'Sol Ring', set: 'cmm'), quantity: 2, binder: Binder.trade),
      CollectionEntry(card('c', 'Island', type: 'Basic Land — Island'), quantity: 30),
      CollectionEntry(card('d', 'Counterspell'), quantity: 1),
    ];
    final d = duplicates(entries, keep: 1);
    expect(d.single.name, 'Sol Ring');
    expect(d.single.copies, 5);
    expect(d.single.extra, 4);
    expect(duplicates(entries, keep: 4).single.extra, 1);
  });

  test('set progress counts different collector numbers', () {
    final entries = [
      CollectionEntry(card('a', 'A', n: '1'), quantity: 4),
      CollectionEntry(card('b', 'B', n: '2'), foil: true),
      CollectionEntry(card('c', 'C', set: 'tdm', n: '7')),
    ];
    final p = setProgress(entries, {'dft': (name: 'Aetherdrift', count: 4)});
    expect(p.first.code, 'dft');
    expect(p.first.owned, 2);
    expect(p.first.fraction, 0.5);
    expect(p.last.total, 0);
  });

  test('value by binder and folder', () {
    final entries = [
      CollectionEntry(card('a', 'A', eur: '2.00'), quantity: 2, folder: 'Sharks'),
      CollectionEntry(card('b', 'B', eur: '5.00'), binder: Binder.trade),
    ];
    expect(valueByBinder(entries).first.label, 'Up for trade');
    expect(valueByFolder(entries).map((r) => r.label), contains('Collection › Sharks'));
  });

  test('folders: auto-sort rule, sort now, rename and delete', () async {
    final store = CollectionStore();
    final blueCheap = const CollectionQuery(colours: {'U'}, maxEur: 3);
    await store.add(card('a', 'Cheap Blue', eur: '1.00'));
    await store.add(card('b', 'Pricey Blue', eur: '9.00'));
    await store.add(card('c', 'Red', ci: ['R']));
    final f = CollectionFolder(name: 'Blue bulk', binder: Binder.collection, rule: blueCheap, autoSort: true);
    await store.saveFolder(f);
    expect(await store.sortIntoFolder(f), 1);
    expect(store.entries.firstWhere((e) => e.card.id == 'a').folder, 'Blue bulk');
    // New matching cards go straight in.
    await store.add(card('d', 'Another Blue', eur: '0.50'));
    expect(store.entries.firstWhere((e) => e.card.id == 'd').folder, 'Blue bulk');
    await store.saveFolder(CollectionFolder(name: 'Blues', binder: Binder.collection, rule: blueCheap), oldName: 'Blue bulk');
    expect(store.countInFolder(Binder.collection, 'Blues'), 2);
    await store.deleteFolder(store.folders.single);
    expect(store.entries.every((e) => e.folder == null), isTrue);
  });

  test('folder rule survives saving', () {
    const q = CollectionQuery(text: 'shark', colours: {'U'}, sets: {'dft'}, minEur: 1, maxEur: 5, foil: FoilFilter.foil);
    final back = CollectionQuery.fromJson(q.toJson());
    expect(back.text, 'shark');
    expect(back.sets, {'dft'});
    expect(back.minEur, 1);
    expect(back.foil, FoilFilter.foil);
  });

  test('wishlist: foil price, alerts and saving', () {
    final w = WishItem('Sol Ring', 1, WishPriority.mustHave, card('a', 'Sol Ring', eur: '2.00'), true, 3.0);
    final c = CardPrint(id: 'a', name: 'Sol Ring', setCode: 'cmm', setName: 'CMM', collectorNumber: '1', rarity: 'u',
        priceEur: '1.00', priceEurFoil: '4.00');
    expect(w.priceOf(c), 4.0);
    w.foil = null;
    expect(w.priceOf(c), 1.0);
    w.lastEur = 3.0;
    final store = WishlistStore();
    store.replaceAll([w]);
    expect(store.alerts((eur) => eur).length, 1);
    final back = WishItem.fromJson(w.toJson());
    expect(back.priority, WishPriority.mustHave);
    expect(back.maxGbp, 3.0);
    expect(back.card?.id, 'a');
  });
}
