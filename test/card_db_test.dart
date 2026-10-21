import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/card_db.dart';

Map<String, dynamic> card(
  String id,
  String name,
  String set,
  String number,
  String released, {
  bool promo = false,
  bool digital = false,
  String setType = 'expansion',
}) =>
    {
      'id': id,
      'name': name,
      'set': set,
      'collector_number': number,
      'rarity': 'rare',
      'prices': {'eur': '1.50', 'eur_foil': null, 'usd': '2.00', 'usd_foil': '5.00'},
      'finishes': ['nonfoil', 'foil'],
      'color_identity': ['U', 'R'],
      'type_line': 'Creature — Shark',
      'cmc': 4.0,
      'mana_cost': '{2}{U}{R}',
      'released_at': released,
      'promo': promo,
      'digital': digital,
      'set_type': setType,
      'image_uris': {'normal': 'x'},
    };

void main() {
  final rows = [
    card('abcd-1', 'Captain Howler', 'old', '12', '2020-01-01'),
    card('abcd-2', 'Captain Howler', 'new', '194', '2025-01-01'),
    card('abcd-3', 'Captain Howler', 'pr', '1p', '2026-01-01', promo: true, setType: 'promo'),
    card('abcd-4', 'Captain Howler', 'arena', '9', '2026-02-01', digital: true),
    {
      ...card('ef01-5', 'Delver of Secrets // Insectile Aberration', 'isd', '51', '2011-09-30'),
      'mana_cost': null,
      'type_line': null,
      'image_uris': null,
      'card_faces': [
        {'mana_cost': '{U}', 'type_line': 'Creature — Human Wizard', 'image_uris': {'normal': 'y'}},
        {'mana_cost': '', 'type_line': 'Creature — Human Insect'},
      ],
    },
  ];
  final text = [
    '#v1\t2026-10-18',
    '#set\tnew\tNew Set',
    for (final r in rows) ?encodeCardRow(r),
  ].join('\n');
  final db = CardDb.parse(text);

  test('digital-only printings are skipped', () {
    expect(db.printingCount, 4);
    expect(db.updatedAt, '2026-10-18');
  });

  test('by set code and number, with leading zeros from the card', () {
    final c = db.byCode('NEW', '0194')!;
    expect(c.id, 'abcd-2');
    expect(c.setName, 'New Set');
    expect(c.priceEur, '1.50');
    expect(c.priceEurFoil, isNull);
    expect(c.colorIdentity, ['U', 'R']);
    expect(c.cmc, 4);
    expect(c.manaCost, '{2}{U}{R}');
    expect(c.imageUrl, 'https://cards.scryfall.io/normal/front/a/b/abcd-2.jpg');
    expect(db.byCode('new', '194')?.id, 'abcd-2');
  });

  test('default printing is the newest normal one; set narrows it', () {
    expect(db.named('captain howler')!.id, 'abcd-2');
    expect(db.named('Captain Howler', set: 'old')!.id, 'abcd-1');
    expect(db.named('Captain Howler', set: 'xyz'), isNull);
    expect(db.printings('Captain Howler').map((c) => c.id), ['abcd-3', 'abcd-2', 'abcd-1']);
  });

  test('double-faced cards: front face name, face cost and type', () {
    final d = db.named('Delver of Secrets')!;
    expect(d.name, 'Delver of Secrets // Insectile Aberration');
    expect(d.manaCost, '{U}');
    expect(d.typeLine, 'Creature — Human Wizard');
    expect(d.imageUrl, isNotNull);
    expect(db.names, contains('Delver of Secrets // Insectile Aberration'));
  });

  test('image sizes swap on Scryfall links only', () {
    expect(imageAtSize('https://cards.scryfall.io/normal/front/a/b/x.jpg?1', 'small'),
        'https://cards.scryfall.io/small/front/a/b/x.jpg?1');
    expect(imageAtSize('https://example.com/normal/x.jpg', 'small'), 'https://example.com/normal/x.jpg');
  });

  test('splits a streamed JSON array however it is chunked or wrapped', () async {
    const text = '[{"a":1,"s":"x}{\\"y"},\n{"b":[1,{"c":2}]}\n,{"d":"]"}]';
    for (final size in [1, 2, 3, 5, 7, 100]) {
      final chunks = [for (var i = 0; i < text.length; i += size) text.substring(i, (i + size).clamp(0, text.length))];
      final objs = await splitJsonArray(Stream.fromIterable(chunks)).toList();
      expect(objs, ['{"a":1,"s":"x}{\\"y"}', '{"b":[1,{"c":2}]}', '{"d":"]"}'], reason: 'chunk size $size');
    }
  });
}
