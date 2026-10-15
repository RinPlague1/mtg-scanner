/// Shared enums and helpers for collection, decks and trading.
library;

import 'dart:math';

/// Which binder a card sits in. Decides what friends see and what is offered.
enum Binder {
  /// Default. Private; only copies no Built deck needs are offered (as spares).
  collection('collection', 'Collection'),

  /// "Not for trade" flex gallery. Friends (and the share link) can see it;
  /// never offered or suggested.
  showcase('showcase', 'Showcase'),

  /// Cards you actively list. Offered first, unless a Built deck needs them.
  trade('trade', 'Up for trade');

  final String id;
  final String label;
  const Binder(this.id, this.label);

  static Binder parse(String? s) =>
      Binder.values.firstWhere((b) => b.id == s, orElse: () => Binder.collection);
}

enum CardCondition {
  nm('NM', 'Near Mint'),
  lp('LP', 'Lightly Played'),
  mp('MP', 'Moderately Played'),
  hp('HP', 'Heavily Played'),
  dmg('DMG', 'Damaged');

  final String code;
  final String label;
  const CardCondition(this.code, this.label);

  static CardCondition parse(String? s) {
    final v = (s ?? '').trim().toLowerCase().replaceAll('_', ' ');
    for (final c in CardCondition.values) {
      if (c.code.toLowerCase() == v || c.label.toLowerCase() == v) return c;
    }
    if (v.startsWith('mint') || v == 'm' || v == 'nm/m') return CardCondition.nm;
    if (v.contains('light') || v == 'ex' || v == 'excellent' || v == 'good') return CardCondition.lp;
    if (v.contains('moderate') || v == 'played' || v == 'pl') return CardCondition.mp;
    if (v.contains('heav')) return CardCondition.hp;
    if (v.contains('dam') || v == 'poor' || v == 'po') return CardCondition.dmg;
    return CardCondition.nm;
  }
}

enum DeckStatus {
  /// Owned cards are reserved; missing cards become wants (top priority).
  built('built', 'Built'),

  /// Planning. Missing cards become wants; nothing is reserved.
  brewing('brewing', 'Brewing'),

  /// Kept for reference. Its cards are released as spares; no wants.
  retired('retired', 'Retired');

  final String id;
  final String label;
  const DeckStatus(this.id, this.label);

  static DeckStatus parse(String? s) =>
      DeckStatus.values.firstWhere((d) => d.id == s, orElse: () => DeckStatus.built);
}

/// Normalised card name used to match cards across printings, decks and
/// friends. Any printing satisfies a deck slot. Double-faced cards match on
/// their front face ("Delver of Secrets // Insectile Aberration" → "delver of secrets").
String nameKey(String name) {
  var n = name.trim().toLowerCase();
  final slash = n.indexOf('//');
  if (slash > 0) n = n.substring(0, slash);
  n = n
      .replaceAll(RegExp(r'[’`]'), "'")
      .replaceAll(RegExp(r'[áàâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return n;
}

/// Simple random id (no extra package needed).
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _rng.nextInt(0x7fffffff).toRadixString(36);
  return '$t$r';
}

final _rng = Random();
