import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/collection.dart';
import '../data/collection_query.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../services.dart';
import '../social/backend.dart';
import 'collection_tools.dart';
import 'import_screen.dart';
import 'scan_review_screen.dart';
import 'share_showcase.dart';
import 'widgets.dart';

class CollectionScreen extends StatefulWidget {
  final AppServices services;
  const CollectionScreen({super.key, required this.services});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  bool _searching = false;
  CollectionQuery _filters = const CollectionQuery();

  /// Multi-select: non-empty = selection mode.
  final Set<CollectionEntry> _selected = {};
  bool _refreshing = false;

  CollectionStore get _store => widget.services.collection;
  bool get _selecting => _selected.isNotEmpty;

  CollectionQuery get _query {
    final st = widget.services.settings;
    return _filters.copyWith(sortBy: st.sortBy, descending: st.sortDescending);
  }

  Future<void> _export() async {
    final file = await _store.exportCsv();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MTG collection export',
      text: 'Moxfield-format CSV (Collection → Import)',
    ));
  }

  Future<void> _refreshDetails() async {
    setState(() => _refreshing = true);
    try {
      final n = await _store.refreshDetails(widget.services.scryfall);
      if (mounted) showMessage(context, 'Updated details for $n cards');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _toggle(CollectionEntry e) => setState(() {
        if (!_selected.remove(e)) _selected.add(e);
      });

  // ───────── Bulk actions ─────────

  Future<void> _bulkMove(Binder b) async {
    final n = _selected.fold(0, (s, e) => s + e.quantity);
    await _store.moveAll(_selected.toList(), binder: b);
    if (!mounted) return;
    setState(_selected.clear);
    showMessage(context, 'Moved $n cards to ${b.label}');
  }

  Future<void> _bulkCondition(CardCondition c) async {
    await _store.moveAll(_selected.toList(), condition: c);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkTag() async {
    await showTagDialog(context, _store, _selected.toList());
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkDelete() async {
    final n = _selected.fold(0, (s, e) => s + e.quantity);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $n cards?'),
        content: const Text('They will be deleted from your collection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.removeAll(_selected.toList());
    if (mounted) setState(_selected.clear);
  }

  // ───────── App bars ─────────

  PreferredSizeWidget _tabs() => TabBar(tabs: [
        Tab(text: 'All (${_store.totalCards})'),
        Tab(text: 'Showcase (${_store.countIn(Binder.showcase)})'),
        Tab(text: 'For trade (${_store.countIn(Binder.trade)})'),
      ]);

  AppBar _selectionBar(BuildContext context, List<CollectionEntry> all) {
    final copies = _selected.fold(0, (s, e) => s + e.quantity);
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length} selected${copies != _selected.length ? ' ($copies cards)' : ''}'),
      actions: [
        IconButton(
          tooltip: 'Select all shown',
          icon: const Icon(Icons.select_all),
          onPressed: () {
            // Only the cards on the tab you're looking at.
            final tab = DefaultTabController.of(context).index;
            final binder = switch (tab) { 1 => Binder.showcase, 2 => Binder.trade, _ => null };
            setState(() => _selected.addAll(binder == null ? all : all.where((e) => e.binder == binder)));
          },
        ),
        PopupMenuButton<Binder>(
          tooltip: 'Move to binder',
          icon: const Icon(Icons.drive_file_move_outline),
          onSelected: _bulkMove,
          itemBuilder: (_) => [
            for (final b in Binder.values) PopupMenuItem(value: b, child: Text('Move to ${b.label}')),
          ],
        ),
        IconButton(tooltip: 'Tags', icon: const Icon(Icons.label_outline), onPressed: _bulkTag),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') _bulkDelete();
            final c = CardCondition.values.where((c) => c.code == v).firstOrNull;
            if (c != null) _bulkCondition(c);
          },
          itemBuilder: (_) => [
            for (final c in CardCondition.values) PopupMenuItem(value: c.code, child: Text('Condition: ${c.label}')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Remove from collection')),
          ],
        ),
      ],
      bottom: _tabs(),
    );
  }

  AppBar _normalBar() {
    final st = widget.services.settings;
    return AppBar(
      title: _searching
          ? TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Name, set, type or tag', border: InputBorder.none),
              onChanged: (v) => setState(() => _filters = _filters.copyWith(text: v.trim())),
            )
          : Text('Collection · ${_store.totalCards}'),
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            _filters = _filters.copyWith(text: '');
          }),
        ),
        IconButton(
          tooltip: 'Filter',
          icon: Badge(
            isLabelVisible: _filters.filterCount > 0,
            label: Text('${_filters.filterCount}'),
            child: const Icon(Icons.filter_list),
          ),
          onPressed: () async {
            final q = await showFilterSheet(context, _filters, _store.allTags);
            if (q != null) setState(() => _filters = q);
          },
        ),
        PopupMenuButton<SortBy>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          onSelected: (s) => s == st.sortBy
              ? st.setCollectionView(descending: !st.sortDescending)
              : st.setCollectionView(sortBy: s, descending: s == SortBy.added || s == SortBy.price),
          itemBuilder: (_) => [
            for (final s in SortBy.values)
              PopupMenuItem(
                value: s,
                child: Row(children: [
                  Expanded(child: Text(s.label)),
                  if (s == st.sortBy) Icon(st.sortDescending ? Icons.arrow_downward : Icons.arrow_upward, size: 18),
                ]),
              ),
          ],
        ),
        IconButton(
          tooltip: st.collectionGrid ? 'List view' : 'Grid view',
          icon: Icon(st.collectionGrid ? Icons.view_list : Icons.grid_view),
          onPressed: () => st.setCollectionView(grid: !st.collectionGrid),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'import':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(services: widget.services)));
              case 'tags':
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ManageTagsScreen(
                    store: _store,
                    onShow: (t) => setState(() => _filters = _filters.cleared().copyWith(tags: {t})),
                  ),
                ));
              case 'details':
                _refreshDetails();
              case 'export':
                _export();
              case 'share':
                shareShowcase(context, widget.services);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'import', child: Text('Import TXT / CSV')),
            const PopupMenuItem(value: 'tags', child: Text('Manage tags')),
            PopupMenuItem(
              value: 'details',
              enabled: _store.missingDetails > 0 && !_refreshing,
              child: Text(_store.missingDetails > 0
                  ? 'Refresh card details (${_store.missingDetails})'
                  : 'Card details up to date'),
            ),
            PopupMenuItem(value: 'export', enabled: !_store.isEmpty, child: const Text('Export CSV')),
            PopupMenuItem(
              value: 'share',
              enabled: _store.countIn(Binder.showcase) > 0,
              child: const Text('Share Showcase'),
            ),
          ],
        ),
      ],
      bottom: _tabs(),
    );
  }

  // ───────── Body ─────────

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return DefaultTabController(
      length: 3,
      child: ListenableBuilder(
        listenable: Listenable.merge([_store, Fx.instance, s.buffer, s.settings]),
        builder: (context, _) {
          // Drop selected entries that no longer exist (moved or removed).
          if (_selected.isNotEmpty) {
            final current = _store.entries.toSet();
            _selected.removeWhere((e) => !current.contains(e));
          }
          final q = _query;
          final all = q.apply(_store.entries);
          final needsDetails = _store.missingDetails > 0 &&
              (q.colours.isNotEmpty ||
                  q.types.isNotEmpty ||
                  q.sortBy == SortBy.colour ||
                  q.sortBy == SortBy.manaValue);
          return PopScope(
            canPop: !_selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(_selected.clear);
            },
            child: Scaffold(
              appBar: _selecting ? _selectionBar(context, all) : _normalBar(),
              body: Column(children: [
                if (!s.buffer.isEmpty && !_selecting)
                  MaterialBanner(
                    leading: const Icon(Icons.inbox),
                    content: Text('${s.buffer.count} scanned cards are waiting to be added'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ScanReviewScreen(buffer: s.buffer, collection: _store, scryfall: s.scryfall),
                        )),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                if (needsDetails)
                  MaterialBanner(
                    leading: const Icon(Icons.info_outline),
                    content: Text('${_store.missingDetails} cards were saved before colour and type were stored, '
                        'so they won\'t match this filter or sort.'),
                    actions: [
                      TextButton(
                        onPressed: _refreshing ? null : _refreshDetails,
                        child: Text(_refreshing ? 'Updating…' : 'Update them'),
                      ),
                    ],
                  ),
                if (q.filterCount > 0 || q.text.isNotEmpty) _activeFilters(q),
                Expanded(
                  child: TabBarView(children: [
                    _view(all, null),
                    _view(all.where((e) => e.binder == Binder.showcase).toList(), Binder.showcase),
                    _view(all.where((e) => e.binder == Binder.trade).toList(), Binder.trade),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _activeFilters(CollectionQuery q) {
    final chips = <Widget>[];
    void chip(String label, CollectionQuery without) => chips.add(Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(label: Text(label), onDeleted: () => setState(() => _filters = without)),
        ));
    if (q.text.isNotEmpty) chip('"${q.text}"', _filters.copyWith(text: ''));
    if (q.colours.isNotEmpty) chip(q.colours.map((c) => colourNames[c]).join(' / '), _filters.copyWith(colours: {}));
    if (q.types.isNotEmpty) chip(q.types.join(' / '), _filters.copyWith(types: {}));
    if (q.rarities.isNotEmpty) chip(q.rarities.join(' / '), _filters.copyWith(rarities: {}));
    if (q.conditions.isNotEmpty) {
      chip(q.conditions.map((c) => c.code).join(' / '), _filters.copyWith(conditions: {}));
    }
    if (q.tags.isNotEmpty) chip(q.tags.join(' / '), _filters.copyWith(tags: {}));
    if (q.foil != FoilFilter.any) {
      chip(q.foil == FoilFilter.foil ? 'Foil' : 'Non-foil', _filters.copyWith(foil: FoilFilter.any));
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          ...chips,
          TextButton(
            onPressed: () => setState(() => _filters = const CollectionQuery()),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _view(List<CollectionEntry> entries, Binder? binder) {
    if (entries.isEmpty) {
      final filtered = _query.filterCount > 0 || _query.text.isNotEmpty;
      if (filtered) return const EmptyState(icon: Icons.filter_list_off, title: 'No cards match these filters');
      return EmptyState(
        icon: binder == Binder.showcase ? Icons.auto_awesome : Icons.collections_bookmark_outlined,
        title: switch (binder) {
          Binder.showcase => 'Nothing in your Showcase yet',
          Binder.trade => 'Nothing up for trade yet',
          _ => 'Nothing here yet',
        },
        body: switch (binder) {
          Binder.showcase =>
            'Showcase cards are for flexing: friends can see them, but they are never offered in trades. '
                'Long-press cards in All to select them, then move them here.',
          Binder.trade => 'Cards here are offered to friends first. Copies a Built deck needs are kept back.',
          _ => 'Scan cards, or import a TXT or CSV list from ManaBox, Moxfield, Deckbox or Archidekt.',
        },
      );
    }
    final count = entries.fold(0, (s, e) => s + e.quantity);
    final value = entries.fold<double>(0.0, (s, e) => s + (e.priceEur ?? 0) * e.quantity);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(children: [
        Text('$count cards'),
        if (!_selecting) ...[
          const SizedBox(width: 8),
          Text('· long-press to select', style: Theme.of(context).textTheme.bodySmall),
        ],
        const Spacer(),
        Text('≈ ${gbp(value)}', style: Theme.of(context).textTheme.titleSmall),
      ]),
    );
    final grid = widget.services.settings.collectionGrid;
    return Column(children: [
      header,
      Expanded(child: grid ? _grid(entries, binder) : _list(entries, binder)),
    ]);
  }

  void _tap(CollectionEntry e) {
    if (_selecting) {
      _toggle(e);
    } else {
      showEntrySheet(context, widget.services, e);
    }
  }

  Widget _list(List<CollectionEntry> entries, Binder? binder) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        final c = e.card;
        final selected = _selected.contains(e);
        final bits = [
          '${c.setCode.toUpperCase()}${c.collectorNumber.isEmpty ? '' : ' #${c.collectorNumber}'}',
          if (e.foil) 'foil',
          if (e.condition != CardCondition.nm) e.condition.code,
          if (binder == null && e.binder != Binder.collection) e.binder.label,
          if (e.priceEur != null) gbp(e.priceEur),
        ];
        return ListTile(
          selected: selected,
          leading: selected ? const SizedBox(width: 36, child: Icon(Icons.check_circle)) : CardThumb(c.imageUrl),
          title: Text(c.name),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bits.join(' · ')),
            if (e.tags.isNotEmpty)
              Text(
                e.tags.map((t) => '#$t').join('  '),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
          ]),
          trailing: Text('×${e.quantity}', style: Theme.of(context).textTheme.titleMedium),
          onTap: () => _tap(e),
          onLongPress: () => _toggle(e),
        );
      },
    );
  }

  Widget _grid(List<CollectionEntry> entries, Binder? binder) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.66,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final selected = _selected.contains(e);
        final img = e.card.imageUrl;
        return GestureDetector(
          onTap: () => _tap(e),
          onLongPress: () => _toggle(e),
          child: Stack(children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: img == null
                    ? Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(6),
                        child: Text(e.card.name, textAlign: TextAlign.center),
                      )
                    : Image.network(
                        img,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Text(e.card.name, textAlign: TextAlign.center),
                        ),
                      ),
              ),
            ),
            if (e.quantity > 1 || e.foil || (binder == null && e.binder != Binder.collection))
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    [
                      if (e.quantity > 1) '×${e.quantity}',
                      if (e.foil) '✦',
                      if (binder == null && e.binder == Binder.showcase) '★',
                      if (binder == null && e.binder == Binder.trade) '⇄',
                    ].join(' '),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            if (selected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.35),
                    border: Border.all(color: cs.primary, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_circle, size: 36, color: Colors.white),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Edit quantity, binder and condition for one entry.
Future<void> showEntrySheet(BuildContext context, AppServices services, CollectionEntry e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _EntrySheet(services: services, entry: e),
  );
}

class _EntrySheet extends StatefulWidget {
  final AppServices services;
  final CollectionEntry entry;
  const _EntrySheet({required this.services, required this.entry});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late int _moveQty = widget.entry.quantity;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final store = widget.services.collection;
    final decksUsing = widget.services.decks.decks
        .where((d) => d.cards.any((c) => c.key == e.nameKey))
        .map((d) => '${d.name} (${d.status.label})')
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardThumb(e.card.imageUrl, width: 90),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.card.name, style: Theme.of(context).textTheme.titleLarge),
                Text('${e.card.setName} (${e.card.setCode.toUpperCase()})${e.foil ? ' · foil' : ''}'),
                Text('In: ${e.binder.label} · ${e.condition.label}'),
                if (e.priceEur != null) Text('${gbp(e.priceEur)} each (Cardmarket)'),
                if (decksUsing.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Used in ${decksUsing.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Quantity'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () async {
                await store.setQuantity(e, e.quantity - 1);
                if (!context.mounted) return;
                if (e.quantity <= 0 || !store.entries.contains(e)) {
                  Navigator.pop(context);
                } else {
                  setState(() => _moveQty = _moveQty.clamp(1, e.quantity));
                }
              },
            ),
            Text('${e.quantity}', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                await store.setQuantity(e, e.quantity + 1);
                setState(() {});
              },
            ),
          ]),
          const Divider(),
          if (e.quantity > 1)
            Row(children: [
              const Text('Copies to move'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _moveQty > 1 ? () => setState(() => _moveQty--) : null,
              ),
              Text('$_moveQty'),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _moveQty < e.quantity ? () => setState(() => _moveQty++) : null,
              ),
            ]),
          const Text('Move to binder'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final b in Binder.values)
              ChoiceChip(
                label: Text(b.label),
                selected: b == e.binder,
                onSelected: b == e.binder
                    ? null
                    : (_) async {
                        await store.move(e, _moveQty, binder: b);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
          ]),
          const SizedBox(height: 12),
          const Text('Condition'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final c in CardCondition.values)
              ChoiceChip(
                label: Text(c.code),
                tooltip: c.label,
                selected: c == e.condition,
                onSelected: c == e.condition
                    ? null
                    : (_) async {
                        await store.move(e, _moveQty, condition: c);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Tags'),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in e.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact),
                ActionChip(
                  avatar: const Icon(Icons.label_outline, size: 16),
                  label: Text(e.tags.isEmpty ? 'Add tag' : 'Edit'),
                  onPressed: () async {
                    await showTagDialog(context, store, [e]);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove from collection'),
            onPressed: () async {
              await store.setQuantity(e, 0);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}
