import 'package:flutter/foundation.dart';

import '../data/collection.dart';
import '../data/decks.dart';
import '../data/json_file.dart';
import '../data/scryfall.dart';
import '../data/trade_logic.dart';
import '../data/wishlist.dart';
import 'backend.dart';

/// Friends, their lists, trades and suggestions. Cached on the phone so the
/// Friends and Trades tabs still show the last known state offline.
class SocialStore extends ChangeNotifier {
  final Backend backend;
  final CollectionStore collection;
  final DeckStore decks;
  final WishlistStore wishlist;
  final ScryfallClient scryfall;

  SocialStore({
    required this.backend,
    required this.collection,
    required this.decks,
    required this.wishlist,
    required this.scryfall,
  });

  final JsonFile _file = JsonFile('social_cache.json');

  List<Friend> friends = [];
  Map<String, FriendLists> lists = {};
  List<Trade> trades = [];
  final Set<String> appliedTrades = {};
  DateTime? lastRefresh;
  String? error;
  bool loading = false;

  List<Friend> get accepted => friends.where((f) => f.accepted).toList();
  List<Friend> get incomingRequests => friends.where((f) => !f.accepted && f.incoming).toList();
  List<Friend> get outgoingRequests => friends.where((f) => !f.accepted && !f.incoming).toList();
  Friend? friend(String id) => friends.where((f) => f.profile.id == id).firstOrNull;
  String nameOf(String id) => friend(id)?.profile.label ?? 'Unknown';

  // ───────── Your lists ─────────

  /// Copies promised away in open trades, per card name.
  Map<String, int> get reservedOut {
    final me = backend.uid;
    final m = <String, int>{};
    if (me == null) return m;
    for (final t in trades.where((t) => t.open)) {
      for (final c in t.iGive(me)) {
        m.update(c.key, (v) => v + c.qty, ifAbsent: () => c.qty);
      }
    }
    return m;
  }

  List<TradeCard> get mySpares => computeSpares(collection.entries, decks.decks, reserved: reservedOut);
  List<WantCard> get myWants => computeWants(collection.entries, decks.decks, wishlist.items);

  List<TradeSuggestion> get suggestions {
    final spares = mySpares;
    final wants = myWants;
    final out = <TradeSuggestion>[];
    for (final f in accepted) {
      final l = lists[f.profile.id] ?? FriendLists.empty;
      final s = suggestTrade(
        friendId: f.profile.id,
        friendName: f.profile.label,
        myWants: wants,
        mySpares: spares,
        friendWants: l.wants,
        friendSpares: l.spares,
      );
      if (s != null) out.add(s);
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // ───────── Persistence ─────────

  Future<void> load() async {
    final data = await _file.open();
    if (data is Map) {
      try {
        friends = ((data['friends'] as List?) ?? const []).map((f) {
          final m = f as Map<String, dynamic>;
          return Friend(Profile.fromJson(m), m['status'] as String, m['incoming'] as bool? ?? false);
        }).toList();
        lists = ((data['lists'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, FriendLists.fromJson(v as Map<String, dynamic>)));
        trades = ((data['trades'] as List?) ?? const [])
            .map((t) => Trade.fromJson(t as Map<String, dynamic>))
            .toList();
        appliedTrades.addAll(((data['applied'] as List?) ?? const []).cast<String>());
        lastRefresh = DateTime.tryParse(data['refreshed'] as String? ?? '');
      } catch (_) {
        // ignore a bad cache
      }
    }
    notifyListeners();
  }

  Future<void> _save() => _file.write({
        'friends': friends
            .map((f) => {
                  'id': f.profile.id,
                  'username': f.profile.username,
                  'display_name': f.profile.displayName,
                  'status': f.status,
                  'incoming': f.incoming,
                })
            .toList(),
        'lists': lists.map((k, v) => MapEntry(k, v.toJson())),
        'trades': trades.map((t) => t.toJson()).toList(),
        'applied': appliedTrades.toList(),
        'refreshed': lastRefresh?.toIso8601String(),
      });

  /// Merge applied-trade ids restored from the server (avoids applying a
  /// trade twice after reinstalling).
  Future<void> mergeApplied(Iterable<String> ids) async {
    appliedTrades.addAll(ids);
    await _save();
  }

  /// Forget cached friends and trades (on sign-out).
  Future<void> clear() async {
    friends = [];
    lists = {};
    trades = [];
    appliedTrades.clear();
    lastRefresh = null;
    notifyListeners();
    await _save();
  }

  // ───────── Refresh ─────────

  Future<void> refresh() async {
    if (!backend.signedIn || loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      friends = await backend.friends();
      lists = await backend.friendLists(accepted.map((f) => f.profile.id).toList());
      trades = await backend.trades();
      await _applyCompletedTrades();
      lastRefresh = DateTime.now();
      await _save();
    } catch (e) {
      error = errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Completed trades update the collection once: given cards leave, received
  /// cards arrive in the collection binder.
  Future<void> _applyCompletedTrades() async {
    final me = backend.uid;
    if (me == null) return;
    final todo = trades.where((t) => t.status == TradeStatus.completed && !appliedTrades.contains(t.id)).toList();
    if (todo.isEmpty) return;

    // Fetch full printings for incoming cards (falls back to the snapshot).
    final ids = {
      for (final t in todo)
        for (final c in t.iGet(me))
          if (c.scryfallId != null) c.scryfallId!,
    };
    var prints = <CardPrint>[];
    try {
      prints = await scryfall.collection(ids.map((id) => {'id': id}).toList());
    } catch (_) {}

    for (final t in todo) {
      await collection.applyTrade(
        out: [
          for (final c in t.iGive(me)) (key: c.key, qty: c.qty, scryfallId: c.scryfallId, foil: c.foil),
        ],
        incoming: [
          for (final c in t.iGet(me))
            (
              card: prints.where((p) => p.id == c.scryfallId).firstOrNull ?? _snapshotPrint(c),
              qty: c.qty,
              foil: c.foil,
            ),
        ],
      );
      appliedTrades.add(t.id);
    }
  }

  CardPrint _snapshotPrint(TradeCard c) => CardPrint(
        id: c.scryfallId ?? 'trade-${c.key}',
        name: c.name,
        setCode: c.setCode ?? '',
        setName: '',
        collectorNumber: '',
        rarity: '',
        imageUrl: c.imageUrl,
        priceEur: c.foil ? null : c.priceEur?.toStringAsFixed(2),
        priceEurFoil: c.foil ? c.priceEur?.toStringAsFixed(2) : null,
      );

  // ───────── Actions (refresh afterwards) ─────────

  Future<String> requestFriend(String username) async {
    final r = await backend.requestFriend(username);
    await refresh();
    return switch (r) {
      'requested' => 'Request sent to $username',
      'accepted' => 'You and $username are now friends',
      'not_found' => 'No user called $username',
      'self' => "That's you",
      'already_friends' => "You're already friends",
      'already_requested' => 'Request already sent',
      _ => r,
    };
  }

  Future<void> respondFriend(Friend f, bool accept) async {
    await backend.respondFriend(f.profile.id, accept);
    await refresh();
  }

  Future<void> removeFriend(Friend f) async {
    await backend.removeFriend(f.profile.id);
    await refresh();
  }

  Future<void> propose({
    required String to,
    required List<TradeCard> give,
    required List<TradeCard> receive,
    String? message,
    String? parentId,
  }) async {
    await backend.proposeTrade(to: to, give: give, receive: receive, message: message, parentId: parentId);
    await refresh();
  }

  Future<void> respondTrade(Trade t, String action) async {
    await backend.respondTrade(t.id, action);
    await refresh();
  }
}
