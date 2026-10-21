import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/combos.dart';
import '../data/deck_view.dart';
import '../data/decks.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/scryfall.dart';
import '../services.dart';
import '../social/backend.dart';
import 'card_detail_sheet.dart';
import 'card_gallery.dart';
import 'deck_add_cards_screen.dart';
import 'printing_picker.dart';
import 'proxy_image.dart';
import 'widgets.dart';

/// One deck: cards grouped by type as a list or as card images, stats,
/// editing (quantities, commander, printing) and export.
class DeckDetailScreen extends StatefulWidget {
  final AppServices services;
  final String deckId;

  /// A friend's shared deck, shown read-only.
  final Deck? friendDeck;
  final String? ownerName;

  const DeckDetailScreen({super.key, required this.services, required this.deckId})
      : friendDeck = null,
        ownerName = null;

  DeckDetailScreen.friend({super.key, required this.services, required Deck deck, required String owner})
      : deckId = deck.id,
        friendDeck = deck,
        ownerName = owner;

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
  bool _grid = false;
  bool _loading = false;
  String? _loadError;

  AppServices get s => widget.services;
  bool get _readOnly => widget.friendDeck != null;
  Deck? get _deck => widget.friendDeck ?? s.decks.byId(widget.deckId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillDetails());
  }

  void _tabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Imported decks only have names; fetch types, costs and images once.
  Future<void> _fillDetails() async {
    final d = _deck;
    if (d == null || d.cards.every((c) => c.card != null) || _loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_readOnly) {
        // A friend's deck: fill in details for viewing only, nothing is saved.
        final missing = d.cards.where((c) => c.card == null).toList();
        final found = await s.scryfall.collection([for (final c in missing) {'name': c.name}]);
        final byKey = {for (final p in found) nameKey(p.name): p};
        d.cards = [for (final c in d.cards) c.card == null && byKey[c.key] != null ? c.copyWith(card: byKey[c.key]) : c];
        return;
      }
      final left = await s.decks.fillDetails(d, s.scryfall);
      if (left > 0) _loadError = "Couldn't find details for $left card${left == 1 ? '' : 's'}";
    } catch (e) {
      _loadError = errorText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s.decks, s.collection]),
      builder: (context, _) {
        final d = _deck;
        if (d == null) return const Scaffold(body: Center(child: Text('Deck deleted')));
        final groups = groupDeck(d);
        final missing = _readOnly
            ? 0
            : d.cards.fold(0, (n, c) {
                final have = s.collection.ownedCount(c.key);
                return n + (c.realNeeded > have ? c.realNeeded - have : 0);
              });
        final value = deckStats(d).valueEur;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.name),
            bottom: TabBar(controller: _tabs, tabs: const [
              Tab(icon: Icon(Icons.style_outlined), text: 'Cards'),
              Tab(icon: Icon(Icons.insights), text: 'Analytics'),
            ]),
            actions: [
              if (_tabs.index == 0)
                IconButton(
                  tooltip: _grid ? 'Show as list' : 'Show card images',
                  icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _grid = !_grid),
                ),
              if (!_readOnly)
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'share' => _toggleShared(d),
                  'rename' => _rename(d),
                  'export' => _export(d),
                  'reload' => _fillDetails(),
                  _ => _delete(d),
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(value: 'share', checked: d.shared, child: const Text('Share with friends')),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'export', child: Text('Export decklist')),
                  if (d.cards.any((c) => c.card == null))
                    const PopupMenuItem(value: 'reload', child: Text('Load card details')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete deck')),
                ],
              ),
            ],
          ),
          floatingActionButton: _readOnly || _tabs.index != 0
              ? null
              : FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Add cards'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DeckAddCardsScreen(services: s, deckId: d.id),
            )),
          ),
          body: TabBarView(controller: _tabs, children: [
            CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _header(d, missing, value)),
            if (d.cards.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.style_outlined,
                  title: 'No cards yet',
                  body: 'Tap "Add cards" to search Scryfall or your collection.',
                ),
              ),
            for (final (group, cards) in groups) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '${group.label} (${cards.fold(0, (n, c) => n + c.qty)})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              if (_grid)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.716,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _gridTile(d, cards[i]),
                      childCount: cards.length,
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: cards.length,
                  itemBuilder: (context, i) => _listTile(d, cards[i]),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ]),
            _analytics(d),
          ]),
        );
      },
    );
  }

  Widget _header(Deck d, int missing, double value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_readOnly)
          SegmentedButton<DeckStatus>(
            segments: [for (final st in DeckStatus.values) ButtonSegment(value: st, label: Text(st.label))],
            selected: {d.status},
            onSelectionChanged: (v) {
              d.status = v.first;
              s.decks.changed();
            },
          ),
        if (_readOnly) Text('${widget.ownerName}\'s deck', style: Theme.of(context).textTheme.bodySmall),
        Text(_readOnly ? 'Tap a card to view it full size and swipe through the deck.'
            : 'Tap a card to view it full size and swipe; hold to edit.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text([
          '${d.cardCount} cards',
          if (value > 0) gbp(value),
          if (d.cards.any((c) => c.proxies > 0)) '${d.cards.fold(0, (n, c) => n + c.proxies.clamp(0, c.qty))} proxies',
          if (!_readOnly) missing == 0 ? 'complete' : '$missing missing',
        ].join(' · '), style: Theme.of(context).textTheme.titleSmall),
        if (!_readOnly && d.shared)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(Icons.people, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              Text('Shared with friends', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        const SizedBox(height: 4),
        if (!_readOnly)
        Text(switch (d.status) {
          DeckStatus.built => missing == 0
              ? 'Owned copies are kept out of trades.'
              : 'Missing cards are on your trade wants (top priority). Owned copies are kept out of trades.',
          DeckStatus.brewing => missing == 0 ? 'Planning.' : 'Missing cards are on your trade wants.',
          DeckStatus.retired => 'Retired: nothing is reserved, and spare copies can be traded.',
        }, style: Theme.of(context).textTheme.bodySmall),
        if (_loading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text('Loading card details…', style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_loadError != null && !_loading)
          Row(children: [
            Expanded(
              child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            TextButton(onPressed: _fillDetails, child: const Text('Retry')),
          ]),
      ]),
    );
  }

  Widget _listTile(Deck d, DeckCard c) {
    final have = s.collection.ownedCount(c.key);
    final short = !_readOnly && have < c.realNeeded;
    final type = c.card?.typeLine ?? '';
    final proxies = c.proxies.clamp(0, c.qty);
    return ListTile(
      dense: true,
      leading: SizedBox(width: 32, child: DeckCardImage(s, c, width: 32, radius: 3)),
      title: Text('${c.qty}× ${c.name}'),
      subtitle: Text(
        [
          if (proxies > 0) proxies == c.qty ? 'proxy' : '$proxies proxy',
          if (type.isNotEmpty) type,
          if (short) have == 0 ? 'missing' : 'own $have',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: short ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: ManaCost(c.card?.manaCost ?? ''),
      onTap: () => _openGallery(d, c),
      onLongPress: _readOnly ? null : () => _cardActions(d, c.key),
    );
  }

  Widget _gridTile(Deck d, DeckCard c) {
    final have = s.collection.ownedCount(c.key);
    final short = !_readOnly && have < c.realNeeded;
    final proxies = c.proxies.clamp(0, c.qty);
    return GestureDetector(
      onTap: () => _openGallery(d, c),
      onLongPress: _readOnly ? null : () => _cardActions(d, c.key),
      child: Stack(children: [
        Positioned.fill(
          child: Opacity(
            opacity: short ? 0.55 : 1,
            child: DeckCardImage(s, c),
          ),
        ),
        if (c.qty > 1)
          Positioned(left: 4, top: 4, child: _badge('×${c.qty}', Colors.black87)),
        if (proxies > 0)
          Positioned(
            right: 4,
            top: 4,
            child: _badge(proxies == c.qty ? 'PROXY' : 'PROXY ×$proxies', Colors.deepPurple),
          ),
        if (short)
          Positioned(
            right: 4,
            bottom: 4,
            child: _badge(have == 0 ? 'missing' : 'own $have', Theme.of(context).colorScheme.error),
          ),
      ]),
    );
  }

  Widget _badge(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
      );

  // ───────── Card actions ─────────

  Future<void> _toggleShared(Deck d) async {
    d.shared = !d.shared;
    await s.decks.changed();
    if (mounted) {
      showMessage(context, d.shared ? 'Friends can now see ${d.name}' : '${d.name} is private again');
    }
  }

  /// Full-screen viewer: swipe through every card in the deck, in the
  /// order shown. Your own deck has an Edit button per card.
  Future<void> _openGallery(Deck d, DeckCard start) {
    final cards = [for (final (_, list) in groupDeck(d)) ...list];
    final i = cards.indexWhere((c) => c.key == start.key);
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CardGalleryScreen(
        count: cards.length,
        initialIndex: i < 0 ? 0 : i,
        image: (ctx, n) => DeckCardImage(s, cards[n], fit: BoxFit.contain, radius: 0, large: true),
        title: (n) => '${cards[n].qty}× ${cards[n].name}${cards[n].commander ? ' · Commander' : ''}',
        subtitle: (n) {
          final c = cards[n];
          final have = s.collection.ownedCount(c.key);
          return [
            if (c.card != null) c.card!.typeLine,
            if (c.proxies > 0) c.proxyImage != null ? 'proxy (their photo)' : 'proxy',
            if (!_readOnly && have < c.realNeeded) have == 0 ? 'missing' : 'own $have',
            if (c.card?.priceEur != null) gbp(double.tryParse(c.card!.priceEur!)),
          ].join(' · ');
        },
        actions: (ctx, n) => [
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline),
            label: const Text('Details'),
            onPressed: () => _openDetails(cards[n]),
          ),
          if (!_readOnly)
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
              onPressed: () => _cardActions(d, cards[n].key),
            ),
        ],
      ),
    ));
  }

  bool _uploading = false;

  Future<void> _uploadProxyImage(Deck d, DeckCard c) async {
    if (_uploading) return;
    if (!s.backend.signedIn) {
      showMessage(context, 'Sign in on the Friends tab to upload proxy photos');
      return;
    }
    try {
      final png = await pickProxyImage();
      if (png == null || !mounted) return;
      _uploading = true;
      showMessage(context, 'Uploading photo…');
      final old = c.proxyImage;
      final path = await s.backend.uploadProxyImage(d.id, c.key, png);
      d.setProxyImage(c.key, path);
      await s.decks.changed();
      if (old != null) unawaited(s.backend.deleteProxyImage(old).catchError((_) {}));
      if (mounted) {
        showMessage(context, d.shared ? 'Photo added. Friends will see it too' : 'Photo added');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      _uploading = false;
    }
  }

  Future<void> _removeProxyImage(Deck d, DeckCard c) async {
    final old = c.proxyImage;
    if (old == null) return;
    d.setProxyImage(c.key, null);
    await s.decks.changed();
    unawaited(s.backend.deleteProxyImage(old).catchError((_) {}));
  }

  /// A friend's card: their proxy photo large, or the card's details.
  Future<void> _showFriendCard(DeckCard c) {
    if (c.proxyImage == null) return _openDetails(c);
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(aspectRatio: 0.716, child: DeckCardImage(s, c)),
            const SizedBox(height: 8),
            Text('${c.name} · proxy', style: Theme.of(ctx).textTheme.titleSmall),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openDetails(c);
              },
              child: const Text('Card details'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _cardActions(Deck d, String key) {
    if (_readOnly) {
      final c = d.byKey(key);
      return c == null ? Future.value() : _showFriendCard(c);
    }
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: s.decks,
        builder: (ctx, _) {
          final c = d.byKey(key);
          if (c == null) return const SizedBox(height: 120, child: Center(child: Text('Removed from the deck')));
          final have = s.collection.ownedCount(key);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 90, child: DeckCardImage(s, c, width: 90, radius: 6)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: Theme.of(ctx).textTheme.titleLarge),
                      if (c.card != null) ...[
                        Text(c.card!.typeLine),
                        const SizedBox(height: 4),
                        ManaCost(c.card!.manaCost),
                        const SizedBox(height: 4),
                        Text('Shown: ${c.card!.setName} (${c.card!.setCode.toUpperCase()})',
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ],
                      Text(have == 0 ? "You don't own this" : 'You own $have',
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Copies in deck'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      d.setQty(key, c.qty - 1);
                      s.decks.changed();
                    },
                  ),
                  Text('${c.qty}', style: Theme.of(ctx).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      d.setQty(key, c.qty + 1);
                      s.decks.changed();
                    },
                  ),
                ]),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Proxies'),
                      Text(
                        'Printed stand-ins, shown as the printing above. They fill the slot without being in '
                        'your collection or on your wants.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: c.proxies > 0
                        ? () {
                            d.setProxies(key, c.proxies - 1);
                            s.decks.changed();
                          }
                        : null,
                  ),
                  Text('${c.proxies.clamp(0, c.qty)}', style: Theme.of(ctx).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: c.proxies < c.qty
                        ? () {
                            d.setProxies(key, c.proxies + 1);
                            s.decks.changed();
                          }
                        : null,
                  ),
                ]),
                if (c.proxies > 0)
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(c.proxyImage == null ? 'Add photo of your proxy' : 'Replace proxy photo'),
                      onPressed: () => _uploadProxyImage(d, c),
                    ),
                    if (c.proxyImage != null)
                      TextButton(onPressed: () => _removeProxyImage(d, c), child: const Text('Remove photo')),
                  ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Commander'),
                  value: c.commander,
                  onChanged: (v) {
                    d.setCommander(key, v);
                    s.decks.changed();
                  },
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Card details'),
                    onPressed: () => _openDetails(c),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Change printing'),
                    onPressed: () => _changePrinting(d, c),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                    onPressed: () {
                      d.setQty(key, 0);
                      s.decks.changed();
                      Navigator.pop(ctx);
                    },
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<CardPrint?> _printFor(DeckCard c) async {
    if (c.card != null) return c.card;
    try {
      return await s.scryfall.named(c.name);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
      return null;
    }
  }

  Future<void> _openDetails(DeckCard c) async {
    final p = await _printFor(c);
    if (p == null || !mounted) return;
    await showCardDetail(context, s, p, forDeckId: _readOnly ? null : widget.deckId);
  }

  Future<void> _changePrinting(Deck d, DeckCard c) async {
    final current = await _printFor(c);
    if (current == null || !mounted) return;
    final picked = await pickPrinting(context, s.scryfall, current);
    if (picked == null) return;
    d.setPrinting(c.key, picked);
    await s.decks.changed();
  }

  // ───────── Stats ─────────

  Widget _analytics(Deck d) {
    if (d.cards.isEmpty) {
      return const EmptyState(
        icon: Icons.insights,
        title: 'Nothing to analyse yet',
        body: 'Add cards to see the mana curve, colours, types, value and combos.',
      );
    }
    return ListView(
      // Keeps the combo lookup and scroll position when switching tabs.
      key: PageStorageKey('analytics-${d.id}'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _DeckStatsView(stats: deckStats(d)),
        const SizedBox(height: 20),
        _CombosSection(deck: d),
      ],
    );
  }

  // ───────── Deck menu ─────────

  Future<void> _export(Deck d) async {
    await SharePlus.instance.share(ShareParams(text: deckToText(d), subject: d.name));
  }

  Future<void> _rename(Deck d) async {
    final c = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename deck'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      d.name = name;
      await s.decks.changed();
    }
  }

  Future<void> _delete(Deck d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${d.name}"?'),
        content: const Text('Your cards stay in your collection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await s.decks.remove(d);
      if (mounted) Navigator.pop(context);
    }
  }
}

class _DeckStatsView extends StatelessWidget {
  final DeckStats stats;
  const _DeckStatsView({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = stats;
    final maxCurve = st.curve.fold(1, (m, v) => v > m ? v : m);
    final pipTotal = st.pips.values.fold(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Deck stats', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text([
        '${st.cards} cards',
        '${st.lands} lands',
        'avg mana value ${st.averageMv.toStringAsFixed(2)}',
        if (st.valueEur > 0) gbp(st.valueEur),
      ].join(' · ')),
      if (st.unknown > 0)
        Text('${st.unknown} cards still loading details', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      Text('Mana curve (non-land)', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 130,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < st.curve.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${st.curve[i]}', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Container(
                    height: 90 * st.curve[i] / maxCurve,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(i == 7 ? '7+' : '$i', style: theme.textTheme.labelSmall),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Text('Colours (mana symbols in costs)', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      if (pipTotal == 0)
        const Text('Colourless')
      else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (final e in st.pips.entries)
                if (e.value > 0) Expanded(flex: e.value, child: Container(color: manaColour(e.key))),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final e in st.pips.entries)
            if (e.value > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                ManaCost('{${e.key}}'),
                const SizedBox(width: 4),
                Text('${e.value} (${(100 * e.value / pipTotal).round()}%)'),
              ]),
        ]),
      ],
      const SizedBox(height: 16),
      Text('Card types', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final g in DeckGroup.values)
          if ((st.groups[g] ?? 0) > 0) Chip(label: Text('${g.label} ${st.groups[g]}')),
      ]),
    ]);
  }
}

/// Combos from Commander Spellbook: ones the deck already has, and ones a
/// single card away.
class _CombosSection extends StatefulWidget {
  final Deck deck;
  const _CombosSection({required this.deck});

  @override
  State<_CombosSection> createState() => _CombosSectionState();
}

class _CombosSectionState extends State<_CombosSection> {
  static final _client = CombosClient();
  late Future<DeckCombos> _future = _client.forDeck(widget.deck);
  bool _showAlmost = false;

  Future<void> _open(Combo c) async {
    await launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication);
  }

  Widget _tile(Combo c, {bool almost = false}) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(almost ? Icons.add_circle_outline : Icons.all_inclusive,
          color: almost ? null : theme.colorScheme.primary),
      title: Text(c.cards.join(' + ')),
      subtitle: Text([
        if (almost && c.missing.isNotEmpty) 'Add ${c.missing.join(', ')}',
        if (c.results.isNotEmpty) c.results.take(3).join(', '),
      ].join(' · ')),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () => _open(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Combos (Commander Spellbook)', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      FutureBuilder<DeckCombos>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Row(children: [
              Expanded(child: Text("Couldn't load combos: ${errorText(snap.error!)}")),
              TextButton(
                onPressed: () => setState(() => _future = _client.forDeck(widget.deck)),
                child: const Text('Retry'),
              ),
            ]);
          }
          if (!snap.hasData) {
            return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          }
          final r = snap.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (r.included.isEmpty)
              const Text('No complete combos in this deck.')
            else ...[
              Text('${r.included.length} in this deck', style: theme.textTheme.bodySmall),
              for (final c in r.included) _tile(c),
            ],
            if (r.almost.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: Icon(_showAlmost ? Icons.expand_less : Icons.expand_more),
                label: Text('${r.almost.length} more need just one card'),
                onPressed: () => setState(() => _showAlmost = !_showAlmost),
              ),
              if (_showAlmost)
                for (final c in r.almost.take(40)) _tile(c, almost: true),
            ],
          ]);
        },
      ),
    ]);
  }
}
