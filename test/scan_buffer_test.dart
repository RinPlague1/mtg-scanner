import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/collection.dart';
import 'package:mtg_dark_scanner/data/models.dart';
import 'package:mtg_dark_scanner/data/scan_buffer.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';

CardPrint card(String id, String name) => CardPrint(
      id: id,
      name: name,
      setCode: 'tst',
      setName: 'Test',
      collectorNumber: '1',
      rarity: 'rare',
      priceEur: '2.00',
    );

void main() {
  test('rescanning the same printing bumps quantity; undo takes one off', () async {
    final b = ScanBuffer();
    final first = await b.add(card('a', 'Sol Ring'));
    final again = await b.add(card('a', 'Sol Ring'));
    expect(identical(first, again), isTrue);
    expect(b.items.length, 1);
    expect(b.count, 2);
    await b.add(card('a', 'Sol Ring'), foil: true);
    expect(b.items.length, 2);
    await b.undo(again);
    expect(b.count, 2);
    expect(b.totalEur, 2.0); // the foil copy has no foil price in this test card
  });

  test('committing moves cards into their chosen binders and empties the list', () async {
    final b = ScanBuffer();
    final c = CollectionStore();
    await b.add(card('a', 'Sol Ring'));
    final lotus = await b.add(card('b', 'Black Lotus'));
    lotus.binder = Binder.showcase;
    lotus.condition = CardCondition.lp;
    final added = await b.commit(c);
    expect(added, 2);
    expect(b.isEmpty, isTrue);
    expect(c.countIn(Binder.collection), 1);
    expect(c.inBinder(Binder.showcase).single.condition, CardCondition.lp);
  });

  test('committing only some items keeps the rest', () async {
    final b = ScanBuffer();
    final c = CollectionStore();
    final one = await b.add(card('a', 'Sol Ring'));
    await b.add(card('b', 'Island'));
    await b.setAll(binder: Binder.trade);
    await b.commit(c, [one]);
    expect(b.items.single.card.name, 'Island');
    expect(c.countIn(Binder.trade), 1);
  });
}
