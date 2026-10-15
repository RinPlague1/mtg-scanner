import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/collection.dart';
import '../data/decks.dart';
import '../data/wishlist.dart';
import 'backend.dart';
import 'social_store.dart';

/// Offline-first sync. The phone is the source of truth: every change is saved
/// locally straight away, then mirrored to Supabase a few seconds later when
/// signed in and online. Failed pushes are retried every two minutes.
class SyncService extends ChangeNotifier {
  final Backend backend;
  final CollectionStore collection;
  final DeckStore decks;
  final WishlistStore wishlist;
  final SocialStore social;

  SyncService({
    required this.backend,
    required this.collection,
    required this.decks,
    required this.wishlist,
    required this.social,
  });

  Timer? _debounce;
  Timer? _retry;
  bool _dirty = true;
  bool syncing = false;
  DateTime? lastSynced;
  String? error;
  String? _signedInAs;

  void start() {
    if (!backend.enabled) return;
    collection.addListener(_changed);
    decks.addListener(_changed);
    wishlist.addListener(_changed);
    social.addListener(_socialChanged);
    backend.addListener(_authChanged);
    _retry = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_dirty) pushNow();
    });
    _authChanged();
  }

  int _appliedCount = 0;
  void _socialChanged() {
    // Applying a trade changes the collection (already handled); a new applied
    // id must also reach the server.
    if (social.appliedTrades.length != _appliedCount) {
      _appliedCount = social.appliedTrades.length;
      _changed();
    }
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), pushNow);
  }

  Future<void> _authChanged() async {
    final id = backend.uid;
    if (id == _signedInAs) return;
    _signedInAs = id;
    if (id == null) return;
    await _onSignedIn();
  }

  /// First sign-in on this phone: restore from the server if the phone is
  /// empty, otherwise upload what's here.
  Future<void> _onSignedIn() async {
    try {
      final mine = await backend.fetchMine();
      final applied = ((mine.private?['applied_trades'] as List?) ?? const []).cast<String>();
      await social.mergeApplied(applied);
      if (collection.isEmpty && decks.decks.isEmpty && (mine.collection.isNotEmpty || mine.decks.isNotEmpty)) {
        await collection.replaceAll(mine.collection.map(CollectionEntry.fromJson).toList());
        await decks.replaceAll(mine.decks.map(Deck.fromJson).toList());
        final wish = ((mine.private?['wishlist'] as List?) ?? const [])
            .map((w) => WishItem.fromJson(w as Map<String, dynamic>))
            .toList();
        await wishlist.replaceAll(wish);
      }
    } catch (e) {
      error = errorText(e);
      notifyListeners();
    }
    await social.refresh();
    await pushNow();
  }

  Future<void> pushNow() async {
    _debounce?.cancel();
    if (!backend.signedIn || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      await backend.replaceCollection(collection.entries.map((e) => e.toServerJson()).toList());
      await backend.replaceDecks(decks.decks.map((d) => d.toJson()).toList());
      await backend.savePrivateState(wishlist.toJson(), social.appliedTrades.toList());
      await backend.publishLists(social.mySpares, social.myWants);
      _dirty = false;
      error = null;
      lastSynced = DateTime.now();
    } catch (e) {
      error = errorText(e);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
