import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/deck_view.dart';
import '../data/decks.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/scryfall.dart';
import '../services.dart';
import '../social/backend.dart';
import 'card_detail_sheet.dart';
import 'deck_add_cards_screen.dart';
import 'printing_picker.dart';
import 'widgets.dart';

/// One deck: cards grouped by type as a list or as card images, stats,
/// editing (quantities, commander, printing) and export.
class DeckDetailScreen extends StatefulWidget {
  final AppServices services;
  final String deckId;
  const DeckDetailScreen({super.key, required this.services, required this.deckId});

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  bool _grid = false;
  bool _loading = false;
  String? _loadError;

  AppServices get s => widget.services;
  Deck? get _deck => s.decks.byId(widget.deckId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillDetails());
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
        final missing = d.cards.fold(0, (n, c) {
          final have = s.collection.ownedCount(c.key);
          return n + (c.qty > have ? c.qty - have : 0);
        });
        final value = deckStats(d).valueEur;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.name),
            actions: [
              IconButton(
                tooltip: _grid ? 'Show as list' : 'Show card images',
                icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _grid = !_grid),
              ),
              IconButton(
                tooltip: 'Stats',
                icon: const Icon(Icons.insights),
                onPressed: () => _showStats(d),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => _rename(d),
                  'export' => _export(d),
                  'reload' => _fillDetails(),
                  _ => _delete(d),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'export', child: Text('Export decklist')),
                  if (d.cards.any((c) => c.card == null))
                    const PopupMenuItem(value: 'reload', child: Text('Load card details')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete deck')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Add cards'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DeckAddCardsScreen(services: s, deckId: d.id),
            )),
          ),
          body: CustomScrollView(slivers: [
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
        );
      },
    );
  }

  Widget _header(Deck d, int missing, double value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<DeckStatus>(
          segments: [for (final st in DeckStatus.values) ButtonSegment(value: st, label: Text(st.label))],
          selected: {d.status},
          onSelectionChanged: (v) {
            d.status = v.first;
            s.decks.changed();
          },
        ),
        const SizedBox(height: 8),
        Text([
          '${d.cardCount} cards',
          if (value > 0) gbp(value),
          missing == 0 ? 'you own them all' : '$missing missing',
        ].join(' · '), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
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
    final short = have < c.qty;
    final type = c.card?.typeLine ?? '';
    return ListTile(
      dense: true,
      leading: CardThumb(c.card?.imageUrl, width: 32),
      title: Text('${c.qty}× ${c.name}'),
      subtitle: Text(
        [
          if (type.isNotEmpty) type,
          if (short) have == 0 ? 'missing' : 'own $have',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: short ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: ManaCost(c.card?.manaCost ?? ''),
      onTap: () => _cardActions(d, c.key),
    );
  }

  Widget _gridTile(Deck d, DeckCard c) {
    final have = s.collection.ownedCount(c.key);
    final short = have < c.qty;
    final img = c.card?.imageUrl;
    return GestureDetector(
      onTap: () => _cardActions(d, c.key),
      child: Stack(children: [
        Positioned.fill(
          child: Opacity(
            opacity: short ? 0.55 : 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img == null
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(6),
                      child: Text(c.name, textAlign: TextAlign.center),
                    )
                  : Image.network(img, fit: BoxFit.cover),
            ),
          ),
        ),
        if (c.qty > 1)
          Positioned(left: 4, top: 4, child: _badge('×${c.qty}', Colors.black87)),
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

  Future<void> _cardActions(Deck d, String key) {
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
                  CardThumb(c.card?.imageUrl, width: 90),
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
    await showCardDetail(context, s, p, forDeckId: widget.deckId);
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

  void _showStats(Deck d) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _DeckStatsView(stats: deckStats(d)),
        ),
      ),
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
