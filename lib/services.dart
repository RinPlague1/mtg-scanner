import 'data/collection.dart';
import 'data/decks.dart';
import 'data/scan_buffer.dart';
import 'data/scryfall.dart';
import 'data/settings.dart';
import 'data/wishlist.dart';
import 'social/backend.dart';
import 'social/social_store.dart';
import 'social/sync.dart';

/// Everything screens need, created once in main().
class AppServices {
  final CollectionStore collection;
  final DeckStore decks;
  final WishlistStore wishlist;
  final ScryfallClient scryfall;
  final AppSettings settings;
  final ScanBuffer buffer;
  final Backend backend;
  final SocialStore social;
  final SyncService sync;

  AppServices._(
    this.collection,
    this.decks,
    this.wishlist,
    this.scryfall,
    this.settings,
    this.buffer,
    this.backend,
    this.social,
    this.sync,
  );

  static Future<AppServices> create() async {
    final collection = CollectionStore();
    final decks = DeckStore();
    final wishlist = WishlistStore();
    final scryfall = ScryfallClient();
    final settings = AppSettings();
    final buffer = ScanBuffer();
    await Future.wait([collection.load(), decks.load(), wishlist.load(), settings.load(), buffer.load()]);

    await Backend.initialize();
    final backend = Backend();
    final social = SocialStore(
      backend: backend,
      collection: collection,
      decks: decks,
      wishlist: wishlist,
      scryfall: scryfall,
    );
    await social.load();
    final sync = SyncService(
      backend: backend,
      collection: collection,
      decks: decks,
      wishlist: wishlist,
      social: social,
    );
    backend.start();
    sync.start();
    return AppServices._(collection, decks, wishlist, scryfall, settings, buffer, backend, social, sync);
  }
}
