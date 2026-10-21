import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/collection.dart';
import '../data/collection_query.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/scryfall.dart';
import '../services.dart';
import '../social/backend.dart';
import 'app_theme.dart';
import 'collection_insights_screen.dart';
import 'collection_tools.dart';
import 'import_screen.dart';
import 'printing_picker.dart';
import 'scan_review_screen.dart';
import 'share_showcase.dart';
import 'start_page.dart';
import 'widgets.dart';
import 'wishlist_screen.dart';
import 'net_image.dart';

class CollectionScreen extends StatefulWidget {
  final AppServices services;

  /// Tab to open on: 0 all, 1 Showcase, 2 For trade.
  final int initialTab;

  /// Folder to show on [initialTab] ("binderId/folder name").
  final String? initialFolder;
  const CollectionScreen({super.key, required this.services, this.initialTab = 0, this.initialFolder});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  bool _searching = false;
  CollectionQuery _filters = const CollectionQuery();

  /// Multi-select: non-empty = selection mode.
  final Set<CollectionEntry> _selected = {};
  bool _refreshing = false;

  /// Folder shown on each tab: null = all, [_unsorted] = cards in no folder,
  /// otherwise "binderId/folder name".
  final Map<int, String?> _folderOnTab = {};
  static const _unsorted = '\u0000unsorted';

  CollectionStore get _store => widget.services.collection;

  @override
  void initState() {
    super.initState();
    if (widget.initialFolder != null) _folderOnTab[widget.initialTab] = widget.initialFolder;
  }
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

  Future<void> _bulkFoil(bool foil) async {
    await _store.setFoilAll(_selected.toList(), foil);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkFolder() async {
    final binders = _selected.map((e) => e.binder).toSet();
    final choice = await _pickFolder(binders.length == 1 ? binders.first : null);
    if (choice == null || !mounted) return;
    final (binder, name) = choice;
    // Folders belong to a binder; cards in other binders stay where they are.
    final fits = _selected.where((e) => binder == null || e.binder == binder).toList();
    await _store.setFolderAll(fits, name);
    if (!mounted) return;
    final skipped = _selected.length - fits.length;
    setState(_selected.clear);
    showMessage(context, [
      name == null ? 'Moved to Unsorted' : 'Moved to $name',
      if (skipped > 0) '$skipped in another binder left as they were',
    ].join('. '));
  }

  Future<void> _bulkExport() async {
    final file = await _store.exportCsv(_selected.toList(), 'selected-cards');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MTG cards',
      text: 'Moxfield-format CSV',
    ));
  }

  /// Folder chooser. Returns (binder, folder name) with name null for
  /// Unsorted; null if cancelled.
  Future<(Binder?, String?)?> _pickFolder(Binder? binder) async {
    final folders = _foldersFor(binder);
    return showModalBottomSheet<(Binder?, String?)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('Unsorted (no folder)'),
            onTap: () => Navigator.pop(ctx, (null, null)),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.name),
              subtitle: binder == null ? Text(f.binder.label) : null,
              onTap: () => Navigator.pop(ctx, (f.binder, f.name)),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder…'),
            onTap: () async {
              final f = await showFolderEditor(context, widget.services, binder: binder ?? Binder.collection);
              if (ctx.mounted) Navigator.pop(ctx, f == null ? null : (f.binder, f.name));
            },
          ),
        ]),
      ),
    );
  }

  /// Defined folders plus any folder names cards carry (e.g. restored from
  /// a backup) for [binder], or every binder when null.
  List<CollectionFolder> _foldersFor(Binder? binder) {
    final out = <CollectionFolder>[...binder == null ? _store.folders : _store.foldersIn(binder)];
    for (final e in _store.entries) {
      final name = e.folder;
      if (name == null || (binder != null && e.binder != binder)) continue;
      if (!out.any((f) => f.binder == e.binder && f.name == name)) out.add(CollectionFolder(name: name, binder: e.binder));
    }
    return out;
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
        IconButton(tooltip: 'Move to folder', icon: const Icon(Icons.folder_outlined), onPressed: _bulkFolder),
        IconButton(tooltip: 'Tags', icon: const Icon(Icons.label_outline), onPressed: _bulkTag),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') _bulkDelete();
            if (v == 'foil') _bulkFoil(true);
            if (v == 'nonfoil') _bulkFoil(false);
            if (v == 'export') _bulkExport();
            final c = CardCondition.values.where((c) => c.code == v).firstOrNull;
            if (c != null) _bulkCondition(c);
          },
          itemBuilder: (_) => [
            for (final c in CardCondition.values) PopupMenuItem(value: c.code, child: Text('Condition: ${c.label}')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'foil', child: Text('Mark as foil')),
            const PopupMenuItem(value: 'nonfoil', child: Text('Mark as non-foil')),
            const PopupMenuItem(value: 'export', child: Text('Export selected (CSV)')),
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
              case 'wishlist':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => WishlistScreen(services: widget.services)));
              case 'insights':
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CollectionInsightsScreen(services: widget.services),
                ));
              case 'prices':
                st.setShowPriceOnCards(!st.showPriceOnCards);
              case 'theme':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThemePickerScreen(settings: st)));
              case 'start':
                showStartPagePicker(context, st);
              case 'images':
                clearImageCache().then((_) {
                  if (mounted) showMessage(context, 'Image cache cleared');
                });
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'wishlist',
              child: Row(children: [
                const Text('Wishlist'),
                const SizedBox(width: 8),
                if (widget.services.wishlist.alerts(Fx.instance.gbp).isNotEmpty)
                  Badge(label: Text('${widget.services.wishlist.alerts(Fx.instance.gbp).length}')),
              ]),
            ),
            const PopupMenuItem(value: 'insights', child: Text('Value, duplicates & sets')),
            CheckedPopupMenuItem(value: 'prices', checked: st.showPriceOnCards, child: const Text('Prices on cards')),
            PopupMenuItem(value: 'theme', child: Text('Colour theme · ${themeById(st.theme).name}')),
            PopupMenuItem(value: 'start', child: Text('Start page · ${startPageLabel(st)}')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'import', child: Text('Import TXT / CSV')),
            const PopupMenuItem(value: 'tags', child: Text('Manage tags')),
            const PopupMenuItem(value: 'images', child: Text('Clear image cache')),
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
      initialIndex: widget.initialTab,
      child: ListenableBuilder(
        listenable: Listenable.merge([_store, Fx.instance, s.buffer, s.settings, s.wishlist]),
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
                    _view(all, null, 0),
                    _view(all.where((e) => e.binder == Binder.showcase).toList(), Binder.showcase, 1),
                    _view(all.where((e) => e.binder == Binder.trade).toList(), Binder.trade, 2),
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
    if (q.sets.isNotEmpty) chip(q.sets.map((x) => x.toUpperCase()).join(' / '), _filters.copyWith(sets: {}));
    if (q.minEur != null || q.maxEur != null) {
      String m(double? v) => v == null ? '' : '£${Fx.instance.gbp(v).toStringAsFixed(2)}';
      chip('${m(q.minEur)}–${m(q.maxEur)}', _filters.copyWith(clearPrice: true));
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

  Widget _view(List<CollectionEntry> inBinder, Binder? binder, int tab) {
    final folderSel = _folderOnTab[tab];
    final entries = folderSel == null
        ? inBinder
        : folderSel == _unsorted
            ? inBinder.where((e) => e.folder == null).toList()
            : inBinder.where((e) => '${e.binder.id}/${e.folder}' == folderSel).toList();
    final bar = _folderBar(inBinder, binder, tab);
    if (entries.isEmpty) {
      return Column(children: [bar, Expanded(child: _emptyView(binder, folderSel != null))]);
    }
    return Column(children: [bar, Expanded(child: _entriesView(entries, binder))]);
  }

  /// Folder chips: All · Unsorted · each folder · new folder.
  Widget _folderBar(List<CollectionEntry> inBinder, Binder? binder, int tab) {
    final folders = _foldersFor(binder);
    final sel = _folderOnTab[tab];
    int count(bool Function(CollectionEntry) t) => inBinder.where(t).fold(0, (n, e) => n + e.quantity);
    if (folders.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New folder'),
            onPressed: () => showFolderEditor(context, widget.services, binder: binder ?? Binder.collection),
          ),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('All'),
              selected: sel == null,
              onSelected: (_) => setState(() => _folderOnTab[tab] = null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('Unsorted ${count((e) => e.folder == null)}'),
              selected: sel == _unsorted,
              onSelected: (_) => setState(() => _folderOnTab[tab] = _unsorted),
            ),
          ),
          for (final f in folders)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () => _folderActions(f),
                child: ChoiceChip(
                  avatar: Icon(f.autoSort ? Icons.auto_awesome : Icons.folder_outlined, size: 16),
                  label: Text('${f.name} ${count((e) => e.binder == f.binder && e.folder == f.name)}'),
                  selected: sel == '${f.binder.id}/${f.name}',
                  onSelected: (_) => setState(() => _folderOnTab[tab] = '${f.binder.id}/${f.name}'),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('Folder'),
            onPressed: () => showFolderEditor(context, widget.services, binder: binder ?? Binder.collection),
          ),
          if (sel != null && sel != _unsorted)
            IconButton(
              tooltip: 'Folder options',
              icon: const Icon(Icons.more_horiz),
              onPressed: () {
                final f = folders.where((x) => '${x.binder.id}/${x.name}' == sel).firstOrNull;
                if (f != null) _folderActions(f);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _folderActions(CollectionFolder f) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(f.name, style: Theme.of(ctx).textTheme.titleMedium), subtitle: Text(f.binder.label)),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit folder & auto-sort rule'), onTap: () => Navigator.pop(ctx, 'edit')),
          if (f.rule != null)
            ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Sort matching cards in now'), onTap: () => Navigator.pop(ctx, 'sort')),
          ListTile(leading: const Icon(Icons.ios_share), title: const Text('Export folder (CSV)'), onTap: () => Navigator.pop(ctx, 'export')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete folder (cards go to Unsorted)'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'edit':
        await showFolderEditor(context, widget.services, binder: f.binder, existing: f);
      case 'sort':
        final n = await _store.sortIntoFolder(f);
        if (mounted) showMessage(context, 'Moved $n cards into ${f.name}');
      case 'export':
        final cards = _store.entries.where((e) => e.binder == f.binder && e.folder == f.name).toList();
        final file = await _store.exportCsv(cards, f.name);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: f.name));
      case 'delete':
        await _store.deleteFolder(f);
        setState(() => _folderOnTab.updateAll((_, x) => x == '${f.binder.id}/${f.name}' ? null : x));
    }
  }

  Widget _emptyView(Binder? binder, bool inFolder) {
    final filtered = _query.filterCount > 0 || _query.text.isNotEmpty;
    if (filtered) return const EmptyState(icon: Icons.filter_list_off, title: 'No cards match these filters');
    if (inFolder) {
      return const EmptyState(
        icon: Icons.folder_open,
        title: 'This folder is empty',
        body: 'Select cards (long-press) and use the folder button, or set an auto-sort rule in the folder options.',
      );
    }
    {
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
  }

  Widget _entriesView(List<CollectionEntry> entries, Binder? binder) {
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
          if (e.folder != null) '📁 ${e.folder}',
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
                    : NetImage(
                        img,
                        fit: BoxFit.cover,
                        loading: (_) => ColoredBox(color: cs.surfaceContainerHighest),
                        fallback: (_) => Container(
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
            if (widget.services.settings.showPriceOnCards && e.priceEur != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                  child: Text(gbp(e.priceEur), style: const TextStyle(color: Colors.white, fontSize: 12)),
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
  /// Replaced when the printing or finish changes (it may merge into another entry).
  late CollectionEntry _entry = widget.entry;
  late int _moveQty = widget.entry.quantity;

  Future<void> _changePrinting() async {
    final picked = await pickPrinting(context, widget.services.scryfall, _entry.card);
    if (picked == null || !mounted) return;
    // Keep the finish if the new printing has it, else use what it does have.
    final foil = (_entry.foil ? canBeFoil(picked) : canBeNonFoil(picked)) ? _entry.foil : defaultFoil(picked);
    await _apply(picked, foil);
  }

  Future<void> _chooseFolder(CollectionEntry e) async {
    final store = widget.services.collection;
    final names = <String>{
      for (final f in store.foldersIn(e.binder)) f.name,
      for (final x in store.entries)
        if (x.binder == e.binder && x.folder != null) x.folder!,
    }.toList()
      ..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('No folder'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final n in names)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(n),
              selected: n == e.folder,
              onTap: () => Navigator.pop(ctx, n),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder…'),
            onTap: () async {
              final f = await showFolderEditor(ctx, widget.services, binder: e.binder);
              if (ctx.mounted) Navigator.pop(ctx, f?.name);
            },
          ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    final name = picked.isEmpty ? null : picked;
    await store.setFolderAll([e], name);
    // The entry was replaced; show the one now holding these copies.
    final now = store.entries
        .where((x) => x.card.id == e.card.id && x.foil == e.foil && x.binder == e.binder && x.condition == e.condition && x.folder == name)
        .firstOrNull;
    if (mounted && now != null) setState(() => _entry = now);
  }

  Future<void> _apply(CardPrint card, bool foil) async {
    final before = _entry.quantity;
    final result = await widget.services.collection.changePrinting(_entry, card, foil: foil);
    if (!mounted) return;
    setState(() {
      _entry = result;
      _moveQty = result.quantity;
    });
    if (result.quantity > before) {
      showMessage(context, 'Merged with the ${result.quantity - before} you already had');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    final store = widget.services.collection;
    final decksUsing = widget.services.decks.decks
        .where((d) => d.cards.any((c) => c.key == e.nameKey))
        .map((d) => '${d.name} (${d.status.label})')
        .toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardThumb(e.card.imageUrl, width: 90),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.card.name, style: Theme.of(context).textTheme.titleLarge),
                Text('${e.card.setName} (${e.card.setCode.toUpperCase()})${e.foil ? ' · foil' : ''}'),
                Text('In: ${e.binder.label}${e.folder != null ? ' › ${e.folder}' : ''} · ${e.condition.label}'),
                if (e.priceEur != null) Text('${gbp(e.priceEur)} each (Cardmarket)'),
                if (decksUsing.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Used in ${decksUsing.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text('Printing #${e.card.collectorNumber} · ${e.card.setCode.toUpperCase()}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: false, label: const Text('Non-foil'), enabled: canBeNonFoil(e.card) || !e.foil),
                ButtonSegment(value: true, label: const Text('Foil'), enabled: canBeFoil(e.card) || e.foil),
              ],
              selected: {e.foil},
              onSelectionChanged: (v) => _apply(e.card, v.first),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Change printing'),
              onPressed: _changePrinting,
            ),
          ]),
          const SizedBox(height: 8),
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
          Row(children: [
            const Icon(Icons.folder_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(e.folder == null ? 'No folder' : 'Folder: ${e.folder}')),
            TextButton(onPressed: () => _chooseFolder(e), child: const Text('Change')),
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

/// Create or edit a folder (name and optional auto-sort rule). Returns the
/// saved folder, or null if cancelled.
Future<CollectionFolder?> showFolderEditor(BuildContext context, AppServices services,
    {required Binder binder, CollectionFolder? existing}) {
  return showModalBottomSheet<CollectionFolder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FolderEditor(services: services, binder: binder, existing: existing),
  );
}

class _FolderEditor extends StatefulWidget {
  final AppServices services;
  final Binder binder;
  final CollectionFolder? existing;
  const _FolderEditor({required this.services, required this.binder, this.existing});

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late Binder _binder = widget.existing?.binder ?? widget.binder;
  late CollectionQuery? _rule = widget.existing?.rule;
  late bool _auto = widget.existing?.autoSort ?? false;
  bool _sortNow = true;

  CollectionStore get _store => widget.services.collection;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _editRule() async {
    final q = await showFilterSheet(context, _rule ?? const CollectionQuery(), _store.allTags,
        title: 'Cards that go in this folder', action: 'Use these', withText: true);
    if (q != null) setState(() => _rule = q.isEmpty ? null : q);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final taken = _store.folderNamed(_binder, name);
    if (taken != null && taken != widget.existing) {
      showMessage(context, 'There\'s already a folder called $name in ${_binder.label}');
      return;
    }
    final f = CollectionFolder(name: name, binder: _binder, rule: _rule, autoSort: _rule != null && _auto);
    await _store.saveFolder(f, oldName: widget.existing?.name);
    var moved = 0;
    if (_rule != null && _sortNow) moved = await _store.sortIntoFolder(f);
    if (!mounted) return;
    if (moved > 0) showMessage(context, 'Moved $moved cards into $name');
    Navigator.pop(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matching = _rule == null
        ? 0
        : _store.entries
            .where((e) => e.binder == _binder && e.folder == null && _rule!.matches(e))
            .fold(0, (n, e) => n + e.quantity);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing == null ? 'New folder' : 'Edit folder', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Sharks, Bulk rares, Box 3', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('In binder'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final b in Binder.values)
              ChoiceChip(
                label: Text(b.label),
                selected: _binder == b,
                onSelected: widget.existing == null ? (_) => setState(() => _binder = b) : null,
              ),
          ]),
          const SizedBox(height: 16),
          Text('Auto-sort', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            _rule == null
                ? 'Optional: choose which cards belong here (colour, type, rarity, set, price, foil, tags, name).'
                : _rule!.describe(money: (v) => gbp(v)),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: Text(_rule == null ? 'Set rule' : 'Change rule'),
              onPressed: _editRule,
            ),
            if (_rule != null) TextButton(onPressed: () => setState(() => _rule = null), child: const Text('No rule')),
          ]),
          if (_rule != null) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sortNow,
              onChanged: (v) => setState(() => _sortNow = v ?? false),
              title: Text('Move matching unsorted cards in now ($matching)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _auto,
              onChanged: (v) => setState(() => _auto = v),
              title: const Text('Sort new cards automatically'),
              subtitle: const Text('Scanned or imported cards that match go straight in'),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _save, child: Text(widget.existing == null ? 'Create folder' : 'Save')),
          ),
        ]),
      ),
    );
  }
}
