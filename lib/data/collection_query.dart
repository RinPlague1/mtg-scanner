/// Sorting and filtering for the collection screen. Pure Dart, unit-tested.
library;

import 'collection.dart';
import 'models.dart';

enum SortBy {
  added('Date added'),
  name('Name'),
  price('Price'),
  setCode('Set'),
  manaValue('Mana value'),
  colour('Colour'),
  rarity('Rarity');

  final String label;
  const SortBy(this.label);
}

/// Card types to filter on, matched against the type line.
const cardTypes = ['Creature', 'Instant', 'Sorcery', 'Artifact', 'Enchantment', 'Planeswalker', 'Land', 'Battle'];

/// Colour filter letters. 'C' = colourless, 'M' = multicolour.
const colourLetters = ['W', 'U', 'B', 'R', 'G', 'C', 'M'];

const rarities = ['common', 'uncommon', 'rare', 'mythic'];

enum FoilFilter { any, foil, nonFoil }

class CollectionQuery {
  final String text;
  final SortBy sortBy;
  final bool descending;
  final Set<String> colours;
  final Set<String> types;
  final Set<String> rarities;
  final Set<CardCondition> conditions;
  final Set<String> tags;
  final FoilFilter foil;

  const CollectionQuery({
    this.text = '',
    this.sortBy = SortBy.added,
    this.descending = true,
    this.colours = const {},
    this.types = const {},
    this.rarities = const {},
    this.conditions = const {},
    this.tags = const {},
    this.foil = FoilFilter.any,
  });

  /// Number of active filters (not counting search text or sort).
  int get filterCount =>
      (colours.isEmpty ? 0 : 1) +
      (types.isEmpty ? 0 : 1) +
      (rarities.isEmpty ? 0 : 1) +
      (conditions.isEmpty ? 0 : 1) +
      (tags.isEmpty ? 0 : 1) +
      (foil == FoilFilter.any ? 0 : 1);

  CollectionQuery copyWith({
    String? text,
    SortBy? sortBy,
    bool? descending,
    Set<String>? colours,
    Set<String>? types,
    Set<String>? rarities,
    Set<CardCondition>? conditions,
    Set<String>? tags,
    FoilFilter? foil,
  }) =>
      CollectionQuery(
        text: text ?? this.text,
        sortBy: sortBy ?? this.sortBy,
        descending: descending ?? this.descending,
        colours: colours ?? this.colours,
        types: types ?? this.types,
        rarities: rarities ?? this.rarities,
        conditions: conditions ?? this.conditions,
        tags: tags ?? this.tags,
        foil: foil ?? this.foil,
      );

  /// Keeps sort and search, drops every filter.
  CollectionQuery cleared() => CollectionQuery(text: text, sortBy: sortBy, descending: descending);

  bool matches(CollectionEntry e) {
    final c = e.card;
    if (text.isNotEmpty) {
      final t = text.toLowerCase();
      final hit = c.name.toLowerCase().contains(t) ||
          c.setCode.toLowerCase() == t ||
          c.setName.toLowerCase().contains(t) ||
          c.typeLine.toLowerCase().contains(t) ||
          e.tags.any((tag) => tag.toLowerCase().contains(t));
      if (!hit) return false;
    }
    if (colours.isNotEmpty) {
      final ci = c.colorIdentity;
      // A card matches if it fits any chosen colour (W/U/B/R/G), or is
      // colourless (C) / multicolour (M) when those are chosen.
      final ok = (colours.contains('C') && ci.isEmpty && c.hasDetails) ||
          (colours.contains('M') && ci.length > 1) ||
          ci.any(colours.contains);
      if (!ok) return false;
    }
    if (types.isNotEmpty) {
      final line = c.typeLine.toLowerCase();
      if (!types.any((t) => line.contains(t.toLowerCase()))) return false;
    }
    if (rarities.isNotEmpty && !rarities.contains(c.rarity)) return false;
    if (conditions.isNotEmpty && !conditions.contains(e.condition)) return false;
    if (tags.isNotEmpty && !tags.any(e.tags.contains)) return false;
    if (foil == FoilFilter.foil && !e.foil) return false;
    if (foil == FoilFilter.nonFoil && e.foil) return false;
    return true;
  }

  List<CollectionEntry> apply(Iterable<CollectionEntry> entries) {
    final out = entries.where(matches).toList();
    int byName(CollectionEntry a, CollectionEntry b) => a.card.name.toLowerCase().compareTo(b.card.name.toLowerCase());
    int primary(CollectionEntry a, CollectionEntry b) => switch (sortBy) {
          SortBy.added => a.added.compareTo(b.added),
          SortBy.name => byName(a, b),
          SortBy.price => (a.priceEur ?? -1).compareTo(b.priceEur ?? -1),
          SortBy.setCode => a.card.setCode.compareTo(b.card.setCode) != 0
              ? a.card.setCode.compareTo(b.card.setCode)
              : _num(a.card.collectorNumber).compareTo(_num(b.card.collectorNumber)),
          SortBy.manaValue => (a.card.cmc ?? 99).compareTo(b.card.cmc ?? 99),
          SortBy.colour => _colourRank(a).compareTo(_colourRank(b)),
          SortBy.rarity => _rarityRank(a.card.rarity).compareTo(_rarityRank(b.card.rarity)),
        };

    // Ties always fall back to name A→Z, whichever way the main sort runs.
    out.sort((a, b) {
      final r = primary(a, b);
      if (r != 0) return descending ? -r : r;
      return byName(a, b);
    });
    return out;
  }
}

int _num(String collectorNumber) => int.tryParse(collectorNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

int _rarityRank(String r) => switch (r) {
      'common' => 0,
      'uncommon' => 1,
      'rare' => 2,
      'mythic' => 3,
      _ => 4,
    };

/// WUBRG order, then multicolour, then colourless, then unknown.
int _colourRank(CollectionEntry e) {
  final ci = e.card.colorIdentity;
  if (!e.card.hasDetails) return 9;
  if (ci.isEmpty) return 7;
  if (ci.length > 1) return 6;
  return const ['W', 'U', 'B', 'R', 'G'].indexOf(ci.first).clamp(0, 5);
}
