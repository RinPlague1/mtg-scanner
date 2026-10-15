import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/trade_logic.dart';

/// A problem to show the user as-is.
class UserError implements Exception {
  final String message;
  const UserError(this.message);
  @override
  String toString() => message;
}

/// Readable message for any error from Supabase or the network.
String errorText(Object e) {
  if (e is UserError) return e.message;
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) return "You're offline";
  return s;
}

class Profile {
  final String id;
  final String username;
  final String? displayName;
  final String? shareToken;

  const Profile({required this.id, required this.username, this.displayName, this.shareToken});

  String get label => displayName?.isNotEmpty == true ? displayName! : username;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        shareToken: j['share_token'] as String?,
      );
}

class Friend {
  final Profile profile;

  /// 'pending' or 'accepted'.
  final String status;

  /// True when they sent the request to you.
  final bool incoming;

  const Friend(this.profile, this.status, this.incoming);

  bool get accepted => status == 'accepted';
}

/// A friend's published spares and wants.
class FriendLists {
  final List<TradeCard> spares;
  final List<WantCard> wants;
  final DateTime? updated;
  const FriendLists(this.spares, this.wants, this.updated);

  static const empty = FriendLists([], [], null);

  factory FriendLists.fromJson(Map<String, dynamic> j) => FriendLists(
        ((j['spares'] as List?) ?? const []).map((e) => TradeCard.fromJson(e as Map<String, dynamic>)).toList(),
        ((j['wants'] as List?) ?? const []).map((e) => WantCard.fromJson(e as Map<String, dynamic>)).toList(),
        DateTime.tryParse(j['updated_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'spares': spares.map((s) => s.toJson()).toList(),
        'wants': wants.map((w) => w.toJson()).toList(),
        'updated_at': updated?.toIso8601String(),
      };
}

enum TradeStatus { proposed, accepted, declined, cancelled, countered, completed }

class Trade {
  final String id;
  final String fromUser;
  final String toUser;
  final TradeStatus status;

  /// Cards [fromUser] gives.
  final List<TradeCard> give;

  /// Cards [toUser] gives.
  final List<TradeCard> receive;
  final String? message;
  final bool fromDone;
  final bool toDone;
  final DateTime created;
  final DateTime updated;

  const Trade({
    required this.id,
    required this.fromUser,
    required this.toUser,
    required this.status,
    required this.give,
    required this.receive,
    this.message,
    this.fromDone = false,
    this.toDone = false,
    required this.created,
    required this.updated,
  });

  bool isFrom(String me) => fromUser == me;
  String otherUser(String me) => fromUser == me ? toUser : fromUser;
  List<TradeCard> iGive(String me) => fromUser == me ? give : receive;
  List<TradeCard> iGet(String me) => fromUser == me ? receive : give;
  bool iMarkedDone(String me) => fromUser == me ? fromDone : toDone;
  bool get open => status == TradeStatus.proposed || status == TradeStatus.accepted;

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        id: j['id'] as String,
        fromUser: j['from_user'] as String,
        toUser: j['to_user'] as String,
        status: TradeStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => TradeStatus.proposed),
        give: ((j['give'] as List?) ?? const []).map((e) => TradeCard.fromJson(e as Map<String, dynamic>)).toList(),
        receive:
            ((j['receive'] as List?) ?? const []).map((e) => TradeCard.fromJson(e as Map<String, dynamic>)).toList(),
        message: j['message'] as String?,
        fromDone: j['from_done'] as bool? ?? false,
        toDone: j['to_done'] as bool? ?? false,
        created: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_user': fromUser,
        'to_user': toUser,
        'status': status.name,
        'give': give.map((c) => c.toJson()).toList(),
        'receive': receive.map((c) => c.toJson()).toList(),
        'message': message,
        'from_done': fromDone,
        'to_done': toDone,
        'created_at': created.toIso8601String(),
        'updated_at': updated.toIso8601String(),
      };
}

/// Thin wrapper over Supabase. Every call throws on network/server errors;
/// callers show the message.
class Backend extends ChangeNotifier {
  Profile? profile;
  StreamSubscription<AuthState>? _sub;

  static Future<void> initialize() async {
    if (!AppConfig.onlineEnabled) return;
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  }

  bool get enabled => AppConfig.onlineEnabled;
  SupabaseClient get _db => Supabase.instance.client;
  User? get user => enabled ? _db.auth.currentUser : null;
  bool get signedIn => user != null;
  String? get uid => user?.id;

  void start() {
    if (!enabled) return;
    _sub = _db.auth.onAuthStateChange.listen((s) async {
      if (s.event == AuthChangeEvent.signedOut) profile = null;
      if (s.session != null && profile == null) {
        try {
          await loadProfile();
        } catch (_) {}
      }
      notifyListeners();
    });
    if (signedIn) loadProfile().catchError((_) => null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ───────── Accounts ─────────

  Future<bool> usernameAvailable(String name) async =>
      (await _db.rpc('username_available', params: {'name': name})) == true;

  /// Returns true when signed in straight away, false when the user must
  /// confirm their email first.
  Future<bool> signUp({required String email, required String password, required String username}) async {
    final u = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(u)) {
      throw const UserError('Usernames are 3–20 letters, numbers or _');
    }
    if (!await usernameAvailable(u)) throw const UserError('That username is taken');
    final res = await _db.auth.signUp(email: email.trim(), password: password, data: {'username': u});
    if (res.session != null) await loadProfile();
    notifyListeners();
    return res.session != null;
  }

  Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
    await loadProfile();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    profile = null;
    notifyListeners();
  }

  Future<Profile?> loadProfile() async {
    final id = uid;
    if (id == null) return null;
    final row = await _db.from('profiles').select().eq('id', id).maybeSingle();
    profile = row == null ? null : Profile.fromJson(row);
    notifyListeners();
    return profile;
  }

  Future<String> regenerateShareToken() async {
    final t = await _db.rpc('regenerate_share_token') as String;
    await loadProfile();
    return t;
  }

  // ───────── Friends ─────────

  Future<List<Friend>> friends() async {
    final rows = await _db.rpc('list_friends') as List;
    return rows.map((r) {
      final m = r as Map<String, dynamic>;
      return Friend(Profile.fromJson(m), m['status'] as String, m['incoming'] as bool? ?? false);
    }).toList();
  }

  /// Returns: requested | accepted | not_found | self | already_friends | already_requested
  Future<String> requestFriend(String username) async =>
      await _db.rpc('request_friend', params: {'target_username': username.trim().toLowerCase()}) as String;

  Future<void> respondFriend(String other, bool accept) =>
      _db.rpc('respond_friend', params: {'other': other, 'accept': accept});

  Future<void> removeFriend(String other) => _db.rpc('remove_friend', params: {'other': other});

  Future<Map<String, FriendLists>> friendLists(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _db.from('public_lists').select().inFilter('user_id', ids);
    return {for (final r in rows) r['user_id'] as String: FriendLists.fromJson(r)};
  }

  /// A friend's Showcase and Up for trade binders.
  Future<List<Map<String, dynamic>>> friendBinders(String id) async {
    final rows = await _db
        .from('collection_items')
        .select('card, qty, foil, binder, condition, added')
        .eq('user_id', id)
        .inFilter('binder', ['showcase', 'trade'])
        .order('added', ascending: false);
    return rows;
  }

  // ───────── Trades ─────────

  Future<List<Trade>> trades() async {
    final rows = await _db.from('trades').select().order('updated_at', ascending: false).limit(200);
    return rows.map(Trade.fromJson).toList();
  }

  Future<String> proposeTrade({
    required String to,
    required List<TradeCard> give,
    required List<TradeCard> receive,
    String? message,
    String? parentId,
  }) async =>
      await _db.rpc('propose_trade', params: {
        'to_user': to,
        'give': give.map((c) => c.toJson()).toList(),
        'receive': receive.map((c) => c.toJson()).toList(),
        'message': (message?.trim().isEmpty ?? true) ? null : message!.trim(),
        'parent': parentId,
      }) as String;

  /// action: accept | decline | cancel | complete
  Future<String> respondTrade(String id, String action) async =>
      await _db.rpc('respond_trade', params: {'trade_id': id, 'action': action}) as String;

  // ───────── Sync ─────────

  Future<void> replaceCollection(List<Map<String, dynamic>> items) =>
      _db.rpc('replace_my_collection', params: {'items': items});

  Future<void> replaceDecks(List<Map<String, dynamic>> decks) =>
      _db.rpc('replace_my_decks', params: {'items': decks});

  Future<void> savePrivateState(List<Map<String, dynamic>> wishlist, List<String> appliedTrades) =>
      _db.rpc('save_private_state', params: {'wishlist': wishlist, 'applied_trades': appliedTrades});

  Future<void> publishLists(List<TradeCard> spares, List<WantCard> wants) => _db.rpc('publish_lists', params: {
        'spares': spares.map((s) => s.toJson()).toList(),
        'wants': wants.map((w) => w.toJson()).toList(),
      });

  /// Everything you own on the server, for restoring onto a new phone.
  Future<({List<Map<String, dynamic>> collection, List<Map<String, dynamic>> decks, Map<String, dynamic>? private})>
      fetchMine() async {
    final id = uid!;
    final c = await _db.from('collection_items').select().eq('user_id', id);
    final d = await _db.from('decks').select('data').eq('user_id', id);
    final p = await _db.from('private_state').select().eq('user_id', id).maybeSingle();
    return (
      collection: c,
      decks: d.map((r) => r['data'] as Map<String, dynamic>).toList(),
      private: p,
    );
  }
}
