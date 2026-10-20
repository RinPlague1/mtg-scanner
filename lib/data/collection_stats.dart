/// Collection statistics: value breakdowns, duplicates and set completion.
/// Pure Dart, unit-tested (test/collection_stats_test.dart).
library;

import 'collection.dart';
import 'models.dart';

class ValueRow {
  final String label;
  final int cards;
  final double eur;
  const ValueRow(this.label, this.cards, this.eur);
}

double _value(CollectionEntry e) => (e.priceEur ?? 0) * e.quantity;

List<ValueRow> _group(Iterable<CollectionEntry> entries, String Function(CollectionEntry) key) {
  final cards = <String, int>{};
  final eur = <String, double>{};
  for (final e in entries) {
    final k = key(e);
    cards.update(k, (v) => v + e.quantity, ifAbsent: () => e.quantity);
    eur.update(k, (v) => v + _value(e), ifAbsent: () => _value(e));
  }
  return [for (final k in cards.keys) ValueRow(k, cards[k]!, eur[k]!)]..sort((a, b) => b.eur.compareTo(a.eur));
}

List<ValueRow> valueByBinder(Iterable<CollectionEntry> entries) => _group(entries, (e) => e.binder.label);

/// "Binder › Folder", unsorted cards under "Binder › Unsorted".
List<ValueRow> valueByFolder(Iterable<CollectionEntry> entries) =>
    _group(entries, (e) => '${e.binder.label} › ${e.folder ?? 'Unsorted'}');

List<ValueRow> valueBySet(Iterable<CollectionEntry> entries) =>
    _group(entries, (e) => e.card.setName.isEmpty ? e.card.setCode.toUpperCase() : e.card.setName);

/// Most valuable entries by price per copy.
List<CollectionEntry> mostValuable(Iterable<CollectionEntry> entries, {int limit = 20}) {
  final list = entries.where((e) => e.priceEur != null).toList()
    ..sort((a, b) => b.priceEur!.compareTo(a.priceEur!));
  return list.take(limit).toList();
}

class Duplicate {
  final String name;
  final int copies;
  final int extra;
  final List<CollectionEntry> entries;
  const Duplicate(this.name, this.copies, this.extra, this.entries);
}

/// Card names you own more than [keep] copies of (basic lands skipped),
/// most extras first. Use keep = 1 for Commander, 4 for 60-card formats.
List<Duplicate> duplicates(Iterable<CollectionEntry> entries, {int keep = 4}) {
  final by = <String, List<CollectionEntry>>{};
  for (final e in entries) {
    if (e.card.typeLine.toLowerCase().contains('basic')) continue;
    by.putIfAbsent(e.nameKey, () => []).add(e);
  }
  final out = <Duplicate>[];
  for (final list in by.values) {
    final n = list.fold(0, (s, e) => s + e.quantity);
    if (n > keep) out.add(Duplicate(list.first.card.name, n, n - keep, list));
  }
  out.sort((a, b) => b.extra != a.extra ? b.extra.compareTo(a.extra) : a.name.compareTo(b.name));
  return out;
}

class SetProgress {
  final String code;
  final String name;
  final int owned;
  final int total;
  const SetProgress(this.code, this.name, this.owned, this.total);
  double get fraction => total == 0 ? 0 : (owned / total).clamp(0, 1).toDouble();
}

/// Different collector numbers owned per set, against each set's size
/// ([setSizes]: code → printed cards). Sets you own nothing from are skipped.
List<SetProgress> setProgress(Iterable<CollectionEntry> entries, Map<String, ({String name, int count})> setSizes) {
  final owned = <String, Set<String>>{};
  final names = <String, String>{};
  for (final e in entries) {
    final code = e.card.setCode.toLowerCase();
    owned.putIfAbsent(code, () => {}).add(e.card.collectorNumber.toLowerCase());
    names.putIfAbsent(code, () => e.card.setName);
  }
  final out = <SetProgress>[
    for (final code in owned.keys)
      SetProgress(
        code,
        setSizes[code]?.name ?? names[code] ?? code.toUpperCase(),
        owned[code]!.length,
        setSizes[code]?.count ?? 0,
      ),
  ];
  out.sort((a, b) => b.fraction != a.fraction ? b.fraction.compareTo(a.fraction) : b.owned.compareTo(a.owned));
  return out;
}

/// Basic duplicates rule: Commander means one of each.
int keepFor(bool commander) => commander ? 1 : 4;

/// Name key of a card, re-exported for screens.
String keyOf(String name) => nameKey(name);
