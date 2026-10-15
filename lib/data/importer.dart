import 'collection.dart';
import 'decks.dart';
import 'list_parser.dart';
import 'models.dart';
import 'scryfall.dart';

class ResolvedImport {
  final List<CollectionEntry> entries;
  final List<ImportLine> unmatched;
  const ResolvedImport(this.entries, this.unmatched);
}

/// Looks up each line on Scryfall (bulk endpoint, 75 per request) and builds
/// collection entries for [binder]. Lines with a Scryfall ID or set +
/// collector number get that exact printing; name-only lines get the default
/// printing.
Future<ResolvedImport> resolveForCollection(
  ScryfallClient scryfall,
  List<ImportLine> lines,
  Binder binder,
) async {
  final usable = lines.where((l) => l.section != 'maybeboard' && l.section != 'tokens').toList();
  Map<String, String> ident(ImportLine l) {
    if (l.scryfallId != null) return {'id': l.scryfallId!};
    if (l.setCode != null && l.collectorNumber != null) {
      return {'set': l.setCode!, 'collector_number': l.collectorNumber!};
    }
    return {'name': l.name, if (l.setCode != null) 'set': l.setCode!};
  }

  // De-duplicate identifiers to keep requests small.
  final idents = <String, Map<String, String>>{};
  for (final l in usable) {
    final i = ident(l);
    idents[i.entries.map((e) => '${e.key}=${e.value.toLowerCase()}').join('&')] = i;
  }
  final cards = await scryfall.collection(idents.values.toList());

  CardPrint? find(ImportLine l) {
    if (l.scryfallId != null) {
      final byId = cards.where((c) => c.id == l.scryfallId).firstOrNull;
      if (byId != null) return byId;
    }
    if (l.setCode != null && l.collectorNumber != null) {
      final bySet = cards
          .where((c) => c.setCode == l.setCode && c.collectorNumber.toLowerCase() == l.collectorNumber!.toLowerCase())
          .firstOrNull;
      if (bySet != null) return bySet;
    }
    final k = nameKey(l.name);
    final byName = cards.where((c) => nameKey(c.name) == k || c.hasName(l.name));
    if (l.setCode != null) {
      final inSet = byName.where((c) => c.setCode == l.setCode).firstOrNull;
      if (inSet != null) return inSet;
    }
    return byName.firstOrNull;
  }

  final entries = <CollectionEntry>[];
  final unmatched = <ImportLine>[];
  for (final l in usable) {
    final c = find(l);
    if (c == null) {
      unmatched.add(l);
    } else {
      entries.add(CollectionEntry(c, foil: l.foil, quantity: l.qty, binder: binder, condition: l.condition));
    }
  }
  return ResolvedImport(entries, unmatched);
}

/// Builds a deck from a parsed list. Decks only need card names, so this works
/// offline. Sideboard, maybeboard and token lines are left out.
Deck deckFromLines(String name, List<ImportLine> lines, DeckStatus status) {
  final merged = <String, DeckCard>{};
  for (final l in lines) {
    if (l.section == 'sideboard' || l.section == 'maybeboard' || l.section == 'tokens') continue;
    final k = nameKey(l.name);
    final prev = merged[k];
    merged[k] = DeckCard(
      prev?.name ?? l.name,
      (prev?.qty ?? 0) + l.qty,
      commander: (prev?.commander ?? false) || l.commander,
    );
  }
  final cards = merged.values.toList()
    ..sort((a, b) {
      if (a.commander != b.commander) return a.commander ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  return Deck(name: name, status: status, cards: cards);
}
