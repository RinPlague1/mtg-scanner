import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/combos.dart';

void main() {
  test('parses included and one-card-away combos', () {
    final deck = {'thassa\'s oracle', 'demonic consultation', 'basalt monolith'};
    final r = parseFindMyCombos({
      'results': {
        'included': [
          {
            'id': '1234-5678',
            'uses': [
              {'card': {'name': "Thassa's Oracle"}, 'quantity': 1},
              {'card': {'name': 'Demonic Consultation'}, 'quantity': 1},
            ],
            'produces': [
              {'feature': {'name': 'Win the game'}},
            ],
            'description': 'Cast Consultation naming a card not in the deck. ',
          },
        ],
        'almostIncluded': [
          {
            'id': '99',
            'uses': [
              {'card': {'name': 'Basalt Monolith'}},
              {'card': {'name': 'Rings of Brighthearth'}},
            ],
            'produces': [
              {'feature': {'name': 'Infinite colorless mana'}},
            ],
          },
          {
            'id': '100',
            'uses': [
              {'card': {'name': 'Card A'}},
              {'card': {'name': 'Card B'}},
            ],
            'produces': [],
          },
        ],
      },
    }, deck);
    expect(r.included.single.cards, ["Thassa's Oracle", 'Demonic Consultation']);
    expect(r.included.single.results, ['Win the game']);
    expect(r.included.single.url, 'https://commanderspellbook.com/combo/1234-5678/');
    expect(r.almost.single.missing, ['Rings of Brighthearth']); // two-card-away combo dropped
  });
}
