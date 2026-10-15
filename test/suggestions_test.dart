import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/suggestions.dart';

void main() {
  test('Captain Howler: shark/pirate types plus discard and combat themes, UR identity', () {
    final q = suggestionQueries(
      colorIdentity: ['U', 'R'],
      typeLine: 'Legendary Creature — Shark Pirate',
      oracleText: 'Ward—{2}, Pay 2 life.\nWhenever you discard one or more cards, target creature gets +2/+0 '
          'until end of turn for each card discarded this way. Whenever that creature deals combat damage '
          'to a player this turn, you draw a card.',
    );
    expect(q.staples, 'id<=ur f:commander -t:basic');
    expect(q.themes.take(3), ['Shark', 'Pirate', 'discard']);
    expect(q.synergy, startsWith('id<=ur f:commander -t:basic (t:shark or t:pirate or (o:discard)'));
  });

  test('generic creature types are skipped and colourless uses id<=c', () {
    final q = suggestionQueries(colorIdentity: [], typeLine: 'Legendary Creature — Human Wizard', oracleText: '');
    expect(q.synergy, isNull);
    expect(q.staples, 'id<=c f:commander -t:basic');
    expect(q.themes, isEmpty);
  });

  test('at most five search parts', () {
    final q = suggestionQueries(
      colorIdentity: ['G'],
      typeLine: 'Legendary Creature — Elf Druid Dragon',
      oracleText: 'landfall token sacrifice graveyard draw a card artifact',
    );
    expect(' or '.allMatches(q.synergy!).length, lessThanOrEqualTo(4));
  });
}
