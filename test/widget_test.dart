// Named widget_test.dart so `flutter create .` doesn't generate its default
// counter-app test (which would reference a MyApp class that doesn't exist).
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/collection.dart';
import 'package:mtg_dark_scanner/data/scryfall.dart';

void main() {
  CardPrint card(String id, String name) => CardPrint(
        id: id,
        name: name,
        setCode: 'dmu',
        setName: 'Dominaria United',
        collectorNumber: '107',
        rarity: 'mythic',
        priceEur: '60.00',
      );

  test('collection merges duplicates and exports Moxfield CSV', () async {
    final store = CollectionStore();
    await store.add(card('a', 'Sheoldred, the Apocalypse'));
    await store.add(card('a', 'Sheoldred, the Apocalypse'));
    await store.add(card('a', 'Sheoldred, the Apocalypse'), foil: true);
    expect(store.entries.length, 2);
    expect(store.totalCards, 3);
    final csv = store.toMoxfieldCsv().trim().split('\n');
    expect(csv.first, '"Count","Name","Edition","Condition","Language","Foil","Collector Number"');
    expect(csv[1], '"2","Sheoldred, the Apocalypse","dmu","Near Mint","English","","107"');
    expect(csv[2], '"1","Sheoldred, the Apocalypse","dmu","Near Mint","English","foil","107"');
  });
}
