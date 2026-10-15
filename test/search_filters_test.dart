import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/search_filters.dart';

void main() {
  test('empty filters add nothing', () {
    expect(const SearchFilters().toQuery(), '');
    expect(const SearchFilters().isEmpty, isTrue);
    expect(combineQuery('sol ring', ''), 'sol ring');
  });

  test('colours, types, rarity, mana value and Commander legality', () {
    const f = SearchFilters(
      colours: {'U', 'R'},
      types: {'Instant', 'Sorcery'},
      rarities: {'rare'},
      manaValues: {3, 1, 7},
      commanderLegal: true,
    );
    expect(f.toQuery(), 'id<=ur (t:instant or t:sorcery) r:rare (mv=1 or mv=3 or mv>=7) f:commander');
    expect(f.toQuery(includeColours: false), '(t:instant or t:sorcery) r:rare (mv=1 or mv=3 or mv>=7) f:commander');
    expect(f.count, 5);
    expect(combineQuery(' t:shark ', f.toQuery()), startsWith('t:shark id<=ur'));
  });

  test('colourless and owned filter', () {
    const f = SearchFilters(colours: {'C'}, owned: OwnedFilter.notOwned);
    expect(f.toQuery(), 'id:c');
    expect(f.count, 2);
    expect(const SearchFilters(colours: {'C', 'G'}).toQuery(), 'id<=g');
  });
}
