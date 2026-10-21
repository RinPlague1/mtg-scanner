import 'package:flutter/material.dart';

import '../data/decks.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../services.dart';
import '../social/backend.dart';
import 'card_gallery.dart';
import 'deck_screen.dart';
import 'share_showcase.dart';
import 'sign_in_panel.dart';
import 'trade_editor_screen.dart';
import 'widgets.dart';
import 'net_image.dart';

class FriendsScreen extends StatefulWidget {
  final AppServices services;
  const FriendsScreen({super.key, required this.services});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _add = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Deferred: refresh() notifies listeners, which must not happen mid-build.
    Future.microtask(widget.services.social.refresh);
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final name = _add.text.trim();
    if (name.isEmpty) return;
    try {
      final msg = await widget.services.social.requestFriend(name);
      _add.clear();
      if (mounted) showMessage(context, msg);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _signOut() async {
    final s = widget.services;
    await s.sync.pushNow();
    await s.backend.signOut();
    await s.social.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.backend, s.social, s.sync]),
      builder: (context, _) {
        if (!s.backend.signedIn) {
          return Scaffold(appBar: AppBar(title: const Text('Friends')), body: SignInPanel(services: s));
        }
        final p = s.backend.profile;
        final social = s.social;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Friends'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'sync':
                      await s.sync.pushNow();
                      await social.refresh();
                    case 'share':
                      await shareShowcase(context, s);
                    case 'newlink':
                      await runGuarded(context, s.backend.regenerateShareToken,
                          success: 'New share link made; old links stop working');
                    case 'signout':
                      await _signOut();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sync', child: Text('Sync now')),
                  PopupMenuItem(value: 'share', child: Text('Share my Showcase')),
                  PopupMenuItem(value: 'newlink', child: Text('Reset Showcase share link')),
                  PopupMenuItem(value: 'signout', child: Text('Sign out')),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: social.refresh,
            child: ListView(children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(p?.label ?? 'Signed in'),
                subtitle: Text([
                  if (p != null) '@${p.username}',
                  if (s.sync.syncing)
                    'syncing…'
                  else if (s.sync.error != null)
                    'not synced: ${s.sync.error}'
                  else if (s.sync.lastSynced != null)
                    'synced'
                  else
                    'waiting to sync',
                ].join(' · ')),
              ),
              if (social.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Showing saved data: ${social.error}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _add,
                      decoration: const InputDecoration(
                        labelText: 'Add a friend by username',
                        prefixText: '@',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addFriend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _addFriend, child: const Text('Add')),
                ]),
              ),
              if (social.incomingRequests.isNotEmpty) ...[
                _header(context, 'Friend requests'),
                for (final f in social.incomingRequests)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text(f.profile.label),
                    subtitle: Text('@${f.profile.username}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close),
                        onPressed: () => runGuarded(context, () => social.respondFriend(f, false)),
                      ),
                      IconButton.filled(
                        tooltip: 'Accept',
                        icon: const Icon(Icons.check, color: Colors.black),
                        onPressed: () => runGuarded(context, () => social.respondFriend(f, true)),
                      ),
                    ]),
                  ),
              ],
              _header(context, 'Friends (${social.accepted.length})'),
              if (social.accepted.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Add friends by their username. Once they accept, you can see each other\'s '
                      'Showcase, Up for trade binder and wants, and trades get suggested.'),
                ),
              for (final f in social.accepted)
                ListTile(
                  leading: CircleAvatar(child: Text(f.profile.label.substring(0, 1).toUpperCase())),
                  title: Text(f.profile.label),
                  subtitle: Text(_friendSummary(f)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FriendProfileScreen(services: s, friend: f),
                  )),
                ),
              if (social.outgoingRequests.isNotEmpty) ...[
                _header(context, 'Waiting for them to accept'),
                for (final f in social.outgoingRequests)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.hourglass_empty)),
                    title: Text('@${f.profile.username}'),
                    trailing: TextButton(
                      onPressed: () => runGuarded(context, () => social.removeFriend(f)),
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
        );
      },
    );
  }

  String _friendSummary(Friend f) {
    final l = widget.services.social.lists[f.profile.id];
    if (l == null) return '@${f.profile.username}';
    final spares = l.spares.fold(0, (n, c) => n + c.qty);
    final wants = l.wants.fold(0, (n, w) => n + w.qty);
    return '@${f.profile.username} · $spares spare · $wants wanted';
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// A friend's Showcase gallery, Up for trade binder and wants.
class FriendProfileScreen extends StatefulWidget {
  final AppServices services;
  final Friend friend;
  const FriendProfileScreen({super.key, required this.services, required this.friend});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  late Future<List<Map<String, dynamic>>> _binders = widget.services.backend.friendBinders(widget.friend.profile.id);
  late Future<List<Deck>> _decks = _loadDecks();

  Future<List<Deck>> _loadDecks() async {
    final rows = await widget.services.backend.friendDecks(widget.friend.profile.id);
    return rows.map(Deck.fromJson).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _decksTab() {
    final f = widget.friend;
    return FutureBuilder<List<Deck>>(
      future: _decks,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: "Couldn't load decks",
            body: errorText(snap.error!),
            action: TextButton(onPressed: () => setState(() => _decks = _loadDecks()), child: const Text('Retry')),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final decks = snap.data!;
        if (decks.isEmpty) {
          return EmptyState(
            icon: Icons.layers_outlined,
            title: 'No shared decks',
            body: '${f.profile.label} hasn\'t shared any decks yet (deck menu → Share with friends).',
          );
        }
        return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final d in decks)
            ListTile(
              leading: d.commanders.isNotEmpty && d.commanders.first.card?.imageUrl != null
                  ? CardThumb(d.commanders.first.card!.imageUrl, width: 32)
                  : const Icon(Icons.layers),
              title: Text(d.name),
              subtitle: Text([
                if (d.commanders.isNotEmpty) d.commanders.map((c) => c.name).join(' & '),
                '${d.cardCount} cards',
                if (d.cards.any((c) => c.proxies > 0)) 'has proxies',
              ].join(' · ')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DeckDetailScreen.friend(services: widget.services, deck: d, owner: f.profile.label),
              )),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final f = widget.friend;
    final lists = s.social.lists[f.profile.id];
    final suggestion = s.social.suggestions.where((x) => x.friendId == f.profile.id).firstOrNull;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(f.profile.label),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'remove') {
                  final ok = await runGuarded(context, () => s.social.removeFriend(f));
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove friend'))],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Matches'),
              Tab(text: 'Showcase'),
              Tab(text: 'For trade'),
              Tab(text: 'Wants'),
              Tab(text: 'Decks'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.swap_horiz),
          label: Text(suggestion == null ? 'Propose trade' : 'Suggested trade'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TradeEditorScreen(
              services: s,
              friendId: f.profile.id,
              initialGive: suggestion?.youGive ?? const [],
              initialGet: suggestion?.theyGive ?? const [],
            ),
          )),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _binders,
          builder: (context, snap) {
            Widget binderView(Binder b) {
              if (snap.hasError) {
                return EmptyState(
                  icon: Icons.cloud_off,
                  title: "Couldn't load ${b.label}",
                  body: errorText(snap.error!),
                  action: TextButton(
                    onPressed: () => setState(() => _binders = s.backend.friendBinders(f.profile.id)),
                    child: const Text('Retry'),
                  ),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!.where((r) => r['binder'] == b.id).toList();
              if (rows.isEmpty) return EmptyState(icon: Icons.inbox, title: 'Nothing in ${b.label}');
              // Every binder is an image gallery; tap a card to view it full size and swipe.
              String? img(Map<String, dynamic> r) => ((r['card'] as Map)['image_uris'] as Map?)?['normal'] as String?;
              String name(Map<String, dynamic> r) => (r['card'] as Map)['name'] as String? ?? '';
              String info(Map<String, dynamic> r) {
                final card = r['card'] as Map<String, dynamic>;
                final foil = r['foil'] as bool? ?? false;
                final prices = (card['prices'] as Map?) ?? const {};
                final eur = double.tryParse('${foil ? prices['eur_foil'] : prices['eur']}');
                return [
                  '${card['set_name'] ?? (card['set'] as String? ?? '').toUpperCase()}',
                  if (foil) 'foil',
                  r['condition'] as String? ?? 'NM',
                  if (eur != null) gbp(eur),
                ].join(' · ');
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.716,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final qty = r['qty'] as int? ?? 1;
                  final foil = r['foil'] as bool? ?? false;
                  final url = img(r);
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CardGalleryScreen(
                        count: rows.length,
                        initialIndex: i,
                        image: (ctx, n) => CardGalleryScreen.networkCard(img(rows[n]), name(rows[n])),
                        title: (n) => '${rows[n]['qty'] ?? 1}× ${name(rows[n])}',
                        subtitle: (n) => info(rows[n]),
                      ),
                    )),
                    child: Stack(children: [
                      Positioned.fill(
                        child: url == null
                            ? Card(child: Center(child: Text(name(r), textAlign: TextAlign.center)))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: NetImage(url, fit: BoxFit.cover),
                              ),
                      ),
                      if (qty > 1 || foil)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                            child: Text([if (qty > 1) '×$qty', if (foil) '✦'].join(' '),
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ]),
                  );
                },
              );
            }

            return TabBarView(children: [
              _matches(lists?.wants ?? const [], snap.data),
              binderView(Binder.showcase),
              binderView(Binder.trade),
              _wants(lists?.wants ?? const []),
              _decksTab(),
            ]);
          },
        ),
      ),
    );
  }

  /// What they want that you own, and what you want that they have.
  Widget _matches(List<WantCard> theirWants, List<Map<String, dynamic>>? theirBinders) {
    final s = widget.services;
    final f = widget.friend;
    final spares = {for (final c in s.social.mySpares) c.key: c.qty};
    final youHave = [
      for (final w in theirWants)
        if (s.collection.ownedCount(w.key) > 0) (want: w, owned: s.collection.ownedCount(w.key), spare: spares[w.key] ?? 0),
    ]..sort((a, b) => (b.spare > 0 ? 1 : 0).compareTo(a.spare > 0 ? 1 : 0));

    // Their Showcase / Up for trade cards, by name.
    final theirs = <String, ({String name, int trade, int showcase, String? image})>{};
    for (final r in theirBinders ?? const <Map<String, dynamic>>[]) {
      final card = r['card'] as Map<String, dynamic>;
      final name = card['name'] as String? ?? '';
      final key = nameKey(name);
      final qty = (r['qty'] as num?)?.toInt() ?? 1;
      final prev = theirs[key] ?? (name: name, trade: 0, showcase: 0, image: (card['image_uris'] as Map?)?['normal'] as String?);
      theirs[key] = r['binder'] == 'trade'
          ? (name: prev.name, trade: prev.trade + qty, showcase: prev.showcase, image: prev.image)
          : (name: prev.name, trade: prev.trade, showcase: prev.showcase + qty, image: prev.image);
    }
    final theyHave = [
      for (final w in s.social.myWants)
        if (theirs[w.key] != null) (want: w, have: theirs[w.key]!),
    ]..sort((a, b) => b.have.trade.compareTo(a.have.trade));

    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
      _heading('${f.profile.label} wants, you have (${youHave.length})'),
      if (youHave.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nothing on their wants is in your collection.')),
      for (final m in youHave)
        ListTile(
          dense: true,
          leading: Icon(m.spare > 0 ? Icons.check_circle : Icons.inventory_2_outlined,
              color: m.spare > 0 ? Colors.greenAccent : null),
          title: Text('${m.want.qty}× ${m.want.name}'),
          subtitle: Text([
            m.spare > 0 ? 'you have ${m.spare} spare' : 'you own ${m.owned}, but your decks or Showcase use them',
            if (m.want.reason.isNotEmpty) 'they: ${m.want.reason}',
          ].join(' · ')),
          trailing: m.want.priority >= 3 ? Icon(Icons.priority_high, color: theme.colorScheme.error) : null,
        ),
      _heading('You want, ${f.profile.label} has (${theyHave.length})'),
      if (theirBinders == null)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (theyHave.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Nothing on your wants is in their Showcase or Up for trade.'),
        ),
      for (final m in theyHave)
        ListTile(
          dense: true,
          leading: CardThumb(m.have.image, width: 32),
          title: Text('${m.want.qty}× ${m.want.name}'),
          subtitle: Text([
            if (m.have.trade > 0) '${m.have.trade} up for trade',
            if (m.have.showcase > 0) '${m.have.showcase} in Showcase (not for trade)',
            m.want.reason,
          ].join(' · ')),
        ),
    ]);
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _wants(List<WantCard> wants) {
    if (wants.isEmpty) return const EmptyState(icon: Icons.favorite_border, title: 'No wants shared yet');
    final mine = {for (final c in widget.services.social.mySpares) c.key};
    return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
      for (final w in wants)
        ListTile(
          dense: true,
          leading: mine.contains(w.key)
              ? const Icon(Icons.check_circle, color: Colors.greenAccent)
              : const Icon(Icons.favorite_border),
          title: Text('${w.qty}× ${w.name}'),
          subtitle: Text(mine.contains(w.key) ? 'You have a spare · ${w.reason}' : w.reason),
        ),
    ]);
  }
}
