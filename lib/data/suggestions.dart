/// Builds Scryfall searches that suggest cards for a Commander deck.
/// Pure Dart, unit-tested (test/suggestions_test.dart).
library;

/// Themes spotted in a commander's rules text, each mapped to a Scryfall
/// search for cards that support it. Checked in order; the first few found are used.
const _themes = <(String, String)>[
  ('discard', 'o:discard'),
  ('+1/+1 counter', 'o:"+1/+1 counter"'),
  ('-1/-1 counter', 'o:"-1/-1 counter"'),
  ('proliferate', 'o:proliferate'),
  ('token', 'o:"create" o:token'),
  ('sacrifice', 'o:sacrifice'),
  ('graveyard', 'o:graveyard'),
  ('draw', 'o:"draw a card"'),
  ('landfall', 'o:landfall'),
  ('lands you control', 'o:"lands you control"'),
  ('artifact', 'o:artifact'),
  ('enchantment', 'o:enchantment'),
  ('equip', 'o:equip'),
  ('aura', 't:aura'),
  ('lifelink', 'o:lifelink'),
  ('gain life', 'o:"gain" o:life'),
  ('instant or sorcery', 't:instant or t:sorcery'),
  ('spell', 'o:"instant or sorcery"'),
  ('flying', 'o:flying'),
  ('attacks', 'o:attacks'),
  ('combat damage', 'o:"combat damage"'),
  ('mill', 'o:mill'),
  ('exile', 'o:exile'),
  ('treasure', 'o:treasure'),
  ('dragon', 't:dragon'),
  ('elemental', 't:elemental'),
  ('ward', 'o:ward'),
];

/// Creature types too generic to search on.
const _boringTypes = {'human', 'wizard', 'warrior', 'soldier', 'advisor', 'noble', 'citizen', 'peasant'};

class DeckSuggestionQueries {
  /// Cards that match the commander's creature types and themes.
  final String? synergy;

  /// Popular Commander cards in the commander's colours.
  final String staples;

  /// Human-readable reasons, e.g. ["Shark", "Pirate", "discard"].
  final List<String> themes;

  const DeckSuggestionQueries({required this.synergy, required this.staples, required this.themes});
}

/// [colorIdentity] like ['U', 'R']; [typeLine] like "Legendary Creature — Shark Pirate".
DeckSuggestionQueries suggestionQueries({
  required List<String> colorIdentity,
  required String typeLine,
  required String oracleText,
}) {
  final ci = colorIdentity.isEmpty ? 'c' : colorIdentity.map((c) => c.toLowerCase()).join();
  final base = 'id<=$ci f:commander -t:basic';

  final themes = <String>[];
  final parts = <String>[];

  // Creature types after the dash: "Legendary Creature — Shark Pirate".
  final dash = typeLine.indexOf('—');
  if (dash >= 0) {
    for (final t in typeLine.substring(dash + 1).trim().split(RegExp(r'\s+'))) {
      final type = t.trim();
      if (type.isEmpty || _boringTypes.contains(type.toLowerCase())) continue;
      themes.add(type);
      parts.add('t:${type.toLowerCase()}');
    }
  }

  final text = oracleText.toLowerCase();
  for (final (word, query) in _themes) {
    if (parts.length >= 5) break;
    if (text.contains(word)) {
      themes.add(word);
      parts.add('($query)');
    }
  }

  return DeckSuggestionQueries(
    synergy: parts.isEmpty ? null : '$base (${parts.join(' or ')})',
    staples: base,
    themes: themes,
  );
}
