import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../services.dart';
import '../social/backend.dart';
import 'share_showcase.dart';
import 'sign_in_panel.dart';
import 'trade_editor_screen.dart';
import 'widgets.dart';

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
                        icon: const Icon(Icons.check),
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

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final f = widget.friend;
    final lists = s.social.lists[f.profile.id];
    final suggestion = s.social.suggestions.where((x) => x.friendId == f.profile.id).firstOrNull;
    return DefaultTabController(
      length: 3,
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
          bottom: const TabBar(tabs: [Tab(text: 'Showcase'), Tab(text: 'For trade'), Tab(text: 'Wants')]),
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
              if (b == Binder.showcase) {
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.66,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final card = rows[i]['card'] as Map<String, dynamic>;
                    final img = (card['image_uris'] as Map?)?['normal'] as String?;
                    final qty = rows[i]['qty'] as int? ?? 1;
                    final foil = rows[i]['foil'] as bool? ?? false;
                    return Stack(children: [
                      Positioned.fill(
                        child: img == null
                            ? Card(child: Center(child: Text(card['name'] as String? ?? '', textAlign: TextAlign.center)))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(img, fit: BoxFit.cover),
                              ),
                      ),
                      if (qty > 1 || foil)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text([if (qty > 1) '×$qty', if (foil) '✦'].join(' ')),
                          ),
                        ),
                    ]);
                  },
                );
              }
              return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final r in rows)
                  Builder(builder: (context) {
                    final card = r['card'] as Map<String, dynamic>;
                    final foil = r['foil'] as bool? ?? false;
                    final prices = (card['prices'] as Map?) ?? const {};
                    final eur = double.tryParse('${foil ? prices['eur_foil'] : prices['eur']}');
                    return ListTile(
                      dense: true,
                      leading: CardThumb((card['image_uris'] as Map?)?['normal'] as String?, width: 32),
                      title: Text('${r['qty']}× ${card['name']}'),
                      subtitle: Text([
                        (card['set'] as String? ?? '').toUpperCase(),
                        if (foil) 'foil',
                        r['condition'] as String? ?? 'NM',
                        if (eur != null) gbp(eur),
                      ].join(' · ')),
                    );
                  }),
              ]);
            }

            return TabBarView(children: [
              binderView(Binder.showcase),
              binderView(Binder.trade),
              _wants(lists?.wants ?? const []),
            ]);
          },
        ),
      ),
    );
  }

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
