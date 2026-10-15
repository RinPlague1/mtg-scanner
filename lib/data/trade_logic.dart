/// Pure trade logic: spares, wants and suggestions. No Flutter, no I/O, so it
/// is fully unit-tested (test/trade_logic_test.dart).
library;

import 'collection.dart';
import 'decks.dart';
import 'models.dart';
import 'wishlist.dart';

/// One printing offered or exchanged in a trade.
class TradeCard {
  final String key;
  final String name;
  final int qty;

  /// True when it comes from the Up for trade binder (actively listed).
  final bool listed;
  final String? scryfallId;
  final String? setCode;
  final String? imageUrl;
  final bool foil;
  final double? priceEur;

  const TradeCard({
    required this.key,
    required this.name,
    required this.qty,
    this.listed = false,
    this.scryfallId,
    this.setCode,
    this.imageUrl,
    this.foil = false,
    this.priceEur,
  });

  TradeCard withQty(int q) => TradeCard(
        key: key,
        name: name,
        qty: q,
        listed: listed,
        scryfallId: scryfallId,
        setCode: setCode,
        imageUrl: imageUrl,
        foil: foil,
        priceEur: priceEur,
      );

  double get totalEur => (priceEur ?? 0) * qty;

  Map<String, dynamic> toJson() => {
        'k': key,
        'n': name,
        'q': qty,
        if (listed) 'l': true,
        if (scryfallId != null) 'id': scryfallId,
        if (setCode != null) 's': setCode,
        if (imageUrl != null) 'img': imageUrl,
        if (foil) 'f': true,
        if (priceEur != null) 'p': priceEur,
      };

  factory TradeCard.fromJson(Map<String, dynamic> j) => TradeCard(
        key: j['k'] as String? ?? nameKey(j['n'] as String? ?? ''),
        name: j['n'] as String? ?? '',
        qty: (j['q'] as num?)?.toInt() ?? 1,
        listed: j['l'] as bool? ?? false,
        scryfallId: j['id'] as String?,
        setCode: j['s'] as String?,
        imageUrl: j['img'] as String?,
        foil: j['f'] as bool? ?? false,
        priceEur: (j['p'] as num?)?.toDouble(),
      );

  static TradeCard fromEntry(CollectionEntry e, int qty) => TradeCard(
        key: e.nameKey,
        name: e.card.name,
        qty: qty,
        listed: e.binder == Binder.trade,
        scryfallId: e.card.id,
        setCode: e.card.setCode,
        imageUrl: e.card.imageUrl,
        foil: e.foil,
        priceEur: e.priceEur,
      );
}

/// A card someone wants, and why.
class WantCard {
  final String key;
  final String name;
  final int qty;

  /// 3 = missing from a Built deck, 2 = Brewing deck or wishlist.
  final int priority;
  final String reason;

  const WantCard({
    required this.key,
    required this.name,
    required this.qty,
    required this.priority,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {'k': key, 'n': name, 'q': qty, 'pr': priority, 'r': reason};

  factory WantCard.fromJson(Map<String, dynamic> j) => WantCard(
        key: j['k'] as String? ?? nameKey(j['n'] as String? ?? ''),
        name: j['n'] as String? ?? '',
        qty: (j['q'] as num?)?.toInt() ?? 1,
        priority: (j['pr'] as num?)?.toInt() ?? 2,
        reason: j['r'] as String? ?? '',
      );
}

/// Copies of each card name needed by decks with the given status.
Map<String, int> deckNeeds(Iterable<Deck> decks, DeckStatus status) {
  final m = <String, int>{};
  for (final d in decks.where((d) => d.status == status)) {
    d.needs.forEach((k, v) => m.update(k, (x) => x + v, ifAbsent: () => v));
  }
  return m;
}

/// Cards you can trade away.
///
/// Built decks reserve copies first (collection binder, then Showcase, then
/// Up for trade — "the deck takes priority"). What's left in the Up for trade
/// binder is listed; what's left in the collection binder is an automatic
/// spare. Showcase cards are never offered. [reserved] holds copies already
/// promised in open trades.
List<TradeCard> computeSpares(
  Iterable<CollectionEntry> entries,
  Iterable<Deck> decks, {
  Map<String, int> reserved = const {},
}) {
  final need = deckNeeds(decks, DeckStatus.built);
  final byKey = <String, List<CollectionEntry>>{};
  for (final e in entries) {
    byKey.putIfAbsent(e.nameKey, () => []).add(e);
  }

  final out = <TradeCard>[];
  byKey.forEach((key, list) {
    int sum(Binder b) => list.where((e) => e.binder == b).fold(0, (s, e) => s + e.quantity);
    final coll = sum(Binder.collection), show = sum(Binder.showcase), trd = sum(Binder.trade);

    var left = need[key] ?? 0;
    final useColl = left < coll ? left : coll;
    left -= useColl;
    final useShow = left < show ? left : show;
    left -= useShow;
    final useTrade = left < trd ? left : trd;

    var spareTrade = trd - useTrade;
    var spareColl = coll - useColl;

    // Copies promised in open trades come off listed cards first.
    var promised = reserved[key] ?? 0;
    final fromTrade = promised < spareTrade ? promised : spareTrade;
    spareTrade -= fromTrade;
    promised -= fromTrade;
    spareColl = (spareColl - promised).clamp(0, spareColl);

    void take(Binder b, int count) {
      var n = count;
      for (final e in list.where((e) => e.binder == b)) {
        if (n == 0) break;
        final q = n < e.quantity ? n : e.quantity;
        out.add(TradeCard.fromEntry(e, q));
        n -= q;
      }
    }

    take(Binder.trade, spareTrade);
    take(Binder.collection, spareColl);
  });

  out.sort((a, b) {
    if (a.listed != b.listed) return a.listed ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return out;
}

/// Cards you want: gaps in Built and Brewing decks plus the manual wishlist.
/// Retired decks add nothing.
List<WantCard> computeWants(
  Iterable<CollectionEntry> entries,
  Iterable<Deck> decks,
  Iterable<WishItem> wishlist,
) {
  final owned = <String, int>{};
  for (final e in entries) {
    owned.update(e.nameKey, (v) => v + e.quantity, ifAbsent: () => e.quantity);
  }

  final names = <String, String>{};
  final built = <String, int>{};
  final brew = <String, int>{};
  final reasons = <String, List<String>>{};
  for (final d in decks) {
    if (d.status == DeckStatus.retired) continue;
    final target = d.status == DeckStatus.built ? built : brew;
    for (final c in d.cards) {
      names.putIfAbsent(c.key, () => c.name);
      target.update(c.key, (v) => v + c.qty, ifAbsent: () => c.qty);
      final r = reasons.putIfAbsent(c.key, () => []);
      final label = '${d.status.label}: ${d.name}';
      if (!r.contains(label)) r.add(label);
    }
  }
  final wish = <String, int>{};
  for (final w in wishlist) {
    names.putIfAbsent(w.key, () => w.name);
    wish.update(w.key, (v) => v + w.qty, ifAbsent: () => w.qty);
  }

  final out = <WantCard>[];
  for (final key in names.keys) {
    final have = owned[key] ?? 0;
    final deckTotal = (built[key] ?? 0) + (brew[key] ?? 0);
    final wishTotal = wish[key] ?? 0;
    final target = deckTotal > wishTotal ? deckTotal : wishTotal;
    final missing = target - have;
    if (missing <= 0) continue;
    final builtGap = (built[key] ?? 0) > have;
    final why = [...?reasons[key], if (wishTotal > 0) 'Wishlist'];
    out.add(WantCard(
      key: key,
      name: names[key]!,
      qty: missing,
      priority: builtGap ? 3 : 2,
      reason: why.join(', '),
    ));
  }
  out.sort((a, b) {
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    return a.name.compareTo(b.name);
  });
  return out;
}

class TradeSuggestion {
  final String friendId;
  final String friendName;

  /// Cards the friend has spare that you want.
  final List<TradeCard> theyGive;

  /// Cards you have spare that the friend wants.
  final List<TradeCard> youGive;
  final int score;

  const TradeSuggestion({
    required this.friendId,
    required this.friendName,
    required this.theyGive,
    required this.youGive,
    required this.score,
  });

  bool get isSwap => theyGive.isNotEmpty && youGive.isNotEmpty;
  double get theyGiveEur => theyGive.fold(0.0, (s, c) => s + c.totalEur);
  double get youGiveEur => youGive.fold(0.0, (s, c) => s + c.totalEur);
}

/// Match [wants] against [spares]. Returns the allocated cards and their score.
(List<TradeCard>, int) _match(List<WantCard> wants, List<TradeCard> spares) {
  final byKey = <String, List<TradeCard>>{};
  for (final s in spares) {
    byKey.putIfAbsent(s.key, () => []).add(s);
  }
  final out = <TradeCard>[];
  var score = 0;
  for (final w in wants) {
    final offers = [...?byKey[w.key]]..sort((a, b) {
        if (a.listed != b.listed) return a.listed ? -1 : 1;
        return (a.priceEur ?? 0).compareTo(b.priceEur ?? 0);
      });
    var left = w.qty;
    for (final o in offers) {
      if (left == 0) break;
      final q = left < o.qty ? left : o.qty;
      out.add(o.withQty(q));
      score += w.priority * q + (o.listed ? q : 0);
      left -= q;
    }
  }
  return (out, score);
}

/// Two-way match between you and one friend. Null when nothing matches.
/// Scoring: Built-deck gap 3 per card, Brewing or wishlist 2, +1 if the card
/// is in the giver's Up for trade binder, +5 when both sides get something.
TradeSuggestion? suggestTrade({
  required String friendId,
  required String friendName,
  required List<WantCard> myWants,
  required List<TradeCard> mySpares,
  required List<WantCard> friendWants,
  required List<TradeCard> friendSpares,
}) {
  final (theyGive, s1) = _match(myWants, friendSpares);
  final (youGive, s2) = _match(friendWants, mySpares);
  if (theyGive.isEmpty && youGive.isEmpty) return null;
  final bonus = theyGive.isNotEmpty && youGive.isNotEmpty ? 5 : 0;
  return TradeSuggestion(
    friendId: friendId,
    friendName: friendName,
    theyGive: theyGive,
    youGive: youGive,
    score: s1 + s2 + bonus,
  );
}
