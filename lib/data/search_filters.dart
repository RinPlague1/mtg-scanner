/// Filters for the Search tab, turned into Scryfall search syntax.
/// Pure Dart, unit-tested (test/search_filters_test.dart).
library;

enum OwnedFilter { any, owned, notOwned }

class SearchFilters {
  /// Colour identity must fit within these (W U B R G). 'C' alone = colourless.
  final Set<String> colours;

  /// Any of these types (Creature, Instant…).
  final Set<String> types;

  /// common / uncommon / rare / mythic.
  final Set<String> rarities;

  /// Mana values 0–6; 7 means "7 or more".
  final Set<int> manaValues;
  final bool commanderLegal;

  /// Applied on the phone after the search (Scryfall doesn't know your collection).
  final OwnedFilter owned;

  const SearchFilters({
    this.colours = const {},
    this.types = const {},
    this.rarities = const {},
    this.manaValues = const {},
    this.commanderLegal = false,
    this.owned = OwnedFilter.any,
  });

  int get count =>
      (colours.isEmpty ? 0 : 1) +
      (types.isEmpty ? 0 : 1) +
      (rarities.isEmpty ? 0 : 1) +
      (manaValues.isEmpty ? 0 : 1) +
      (commanderLegal ? 1 : 0) +
      (owned == OwnedFilter.any ? 0 : 1);

  bool get isEmpty => count == 0;

  SearchFilters copyWith({
    Set<String>? colours,
    Set<String>? types,
    Set<String>? rarities,
    Set<int>? manaValues,
    bool? commanderLegal,
    OwnedFilter? owned,
  }) =>
      SearchFilters(
        colours: colours ?? this.colours,
        types: types ?? this.types,
        rarities: rarities ?? this.rarities,
        manaValues: manaValues ?? this.manaValues,
        commanderLegal: commanderLegal ?? this.commanderLegal,
        owned: owned ?? this.owned,
      );

  /// Scryfall syntax for everything except [owned]. Set [includeColours] to
  /// false when the colours already come from elsewhere (deck suggestions).
  String toQuery({bool includeColours = true}) {
    final parts = <String>[];
    if (includeColours && colours.isNotEmpty) {
      final c = colours.where((x) => x != 'C').map((x) => x.toLowerCase()).join();
      parts.add(c.isEmpty ? 'id:c' : 'id<=$c');
    }
    String anyOf(Iterable<String> terms) => terms.length == 1 ? terms.first : '(${terms.join(' or ')})';
    if (types.isNotEmpty) parts.add(anyOf(types.map((t) => 't:${t.toLowerCase()}')));
    if (rarities.isNotEmpty) parts.add(anyOf(rarities.map((r) => 'r:$r')));
    if (manaValues.isNotEmpty) {
      final sorted = manaValues.toList()..sort();
      parts.add(anyOf(sorted.map((v) => v >= 7 ? 'mv>=7' : 'mv=$v')));
    }
    if (commanderLegal) parts.add('f:commander');
    return parts.join(' ');
  }
}

/// Joins the user's text and the filter syntax into one Scryfall query.
String combineQuery(String text, String filters) => [text.trim(), filters.trim()].where((s) => s.isNotEmpty).join(' ');
