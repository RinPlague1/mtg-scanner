import 'package:flutter/material.dart';

import '../data/collection.dart';
import '../data/collection_stats.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../services.dart';
import 'app_theme.dart';
import 'collection_insights_screen.dart';
import 'collection_screen.dart';
import 'import_screen.dart';
import 'scan_review_screen.dart';
import 'start_page.dart';
import 'widgets.dart';
import 'wishlist_screen.dart';

/// The Collection tab's front page: value, binders, folders, recent and
/// top cards. "View collection" (or any binder / folder) opens the full list.
class CollectionSummaryScreen extends StatelessWidget {
  final AppServices services;
  const CollectionSummaryScreen({super.key, required this.services});

  CollectionStore get _store => services.collection;

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _open(BuildContext context, {int tab = 0, String? folder}) =>
      _push(context, CollectionScreen(services: services, initialTab: tab, initialFolder: folder));

  static int tabFor(Binder b) => switch (b) {
        Binder.showcase => 1,
        Binder.trade => 2,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final s = services;
    return ListenableBuilder(
      listenable: Listenable.merge([_store, Fx.instance, s.buffer, s.settings, s.wishlist]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final entries = _store.entries;
        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/logo/binderbound_icon.png', width: 32, height: 32),
              ),
              const SizedBox(width: 10),
              const Text('Binderbound'),
            ]),
            actions: [
              IconButton(
                tooltip: 'View collection',
                icon: const Icon(Icons.search),
                onPressed: () => _open(context),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'start':
                      showStartPagePicker(context, s.settings);
                    case 'theme':
                      _push(context, ThemePickerScreen(settings: s.settings));
                    case 'import':
                      _push(context, ImportScreen(services: s));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'start', child: Text('Start page · ${startPageLabel(s.settings)}')),
                  PopupMenuItem(value: 'theme', child: Text('Colour theme · ${themeById(s.settings.theme).name}')),
                  const PopupMenuItem(value: 'import', child: Text('Import TXT / CSV')),
                ],
              ),
            ],
          ),
          body: entries.isEmpty
              ? EmptyState(
                  icon: Icons.collections_bookmark_outlined,
                  title: 'Your collection is empty',
                  body: 'Scan cards on the Scan tab, or import a list from Moxfield, ManaBox or a text file.',
                  action: FilledButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import'),
                    onPressed: () => _push(context, ImportScreen(services: s)),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  _hero(context, theme),
                  if (!s.buffer.isEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.inbox),
                        title: Text('${s.buffer.count} scanned cards waiting'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(
                          context,
                          ScanReviewScreen(buffer: s.buffer, collection: _store, scryfall: s.scryfall),
                        ),
                      ),
                    ),
                  ],
                  _section(theme, 'Binders'),
                  _binders(context, entries),
                  ..._folders(context, theme),
                  _section(theme, 'Recently added'),
                  _recent(context, entries),
                  _section(theme, 'Most valuable'),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (final e in mostValuable(entries, limit: 5))
                        ListTile(
                          dense: true,
                          leading: CardThumb(e.card.imageUrl, width: 32),
                          title: Text(e.card.name),
                          subtitle: Text('${e.card.setCode.toUpperCase()}${e.foil ? ' · foil' : ''} · ${e.binder.label}'),
                          trailing: Text(gbp(e.priceEur)),
                        ),
                    ]),
                  ),
                  _section(theme, 'More'),
                  _links(context),
                ]),
        );
      },
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title, style: theme.textTheme.titleSmall),
      );

  Widget _hero(BuildContext context, ThemeData theme) {
    final unique = _store.entries.map((e) => e.card.name).toSet().length;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Collection value', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text(gbp(_store.totalEur),
              style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text('${_store.totalCards} cards · $unique different',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('View collection'),
            onPressed: () => _open(context),
          ),
        ]),
      ),
    );
  }

  Widget _binders(BuildContext context, List<CollectionEntry> entries) {
    double value(Iterable<CollectionEntry> es) => es.fold(0.0, (v, e) => v + (e.priceEur ?? 0) * e.quantity);
    Widget tile(IconData icon, String label, Iterable<CollectionEntry> es, int tab) => Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context, tab: tab),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon),
                  const SizedBox(height: 8),
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  Text('${es.fold(0, (n, e) => n + e.quantity)} cards'),
                  Text(gbp(value(es)), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.collections_bookmark_outlined, 'All', entries, 0),
      tile(Icons.star_outline, 'Showcase', entries.where((e) => e.binder == Binder.showcase), 1),
      tile(Icons.swap_horiz, 'For trade', entries.where((e) => e.binder == Binder.trade), 2),
    ]);
  }

  List<Widget> _folders(BuildContext context, ThemeData theme) {
    final folders = _store.folders;
    if (folders.isEmpty) return const [];
    return [
      _section(theme, 'Folders'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final f in folders)
            ListTile(
              leading: Icon(f.autoSort ? Icons.auto_awesome : Icons.folder_outlined),
              title: Text(f.name),
              subtitle: Text(f.binder.label),
              trailing: Text('${_store.countInFolder(f.binder, f.name)}'),
              onTap: () => _open(context, tab: tabFor(f.binder), folder: '${f.binder.id}/${f.name}'),
            ),
        ]),
      ),
    ];
  }

  Widget _recent(BuildContext context, List<CollectionEntry> entries) {
    final recent = [...entries]..sort((a, b) => b.added.compareTo(a.added));
    final shown = recent.take(12).toList();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _open(context),
          child: Tooltip(message: shown[i].card.name, child: CardThumb(shown[i].card.imageUrl, width: 84)),
        ),
      ),
    );
  }

  Widget _links(BuildContext context) {
    final alerts = services.wishlist.alerts(Fx.instance.gbp).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: const Text('Wishlist'),
          subtitle: Text('${services.wishlist.items.length} cards'
              '${alerts > 0 ? ' · $alerts price alert${alerts == 1 ? '' : 's'}' : ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(context, WishlistScreen(services: services)),
        ),
        ListTile(
          leading: const Icon(Icons.insights),
          title: const Text('Value, duplicates & sets'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(context, CollectionInsightsScreen(services: services)),
        ),
      ]),
    );
  }
}
