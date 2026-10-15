import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/collection.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../services.dart';
import 'import_screen.dart';
import 'share_showcase.dart';
import 'widgets.dart';

class CollectionScreen extends StatefulWidget {
  final AppServices services;
  const CollectionScreen({super.key, required this.services});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  String _query = '';
  bool _searching = false;

  CollectionStore get _store => widget.services.collection;

  Future<void> _export() async {
    final file = await _store.exportCsv();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MTG collection export',
      text: 'Moxfield-format CSV (Collection → Import)',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: ListenableBuilder(
        listenable: Listenable.merge([_store, Fx.instance]),
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(
              title: _searching
                  ? TextField(
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Search your cards', border: InputBorder.none),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    )
                  : Text('Collection · ${_store.totalCards}'),
              actions: [
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search',
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    _query = '';
                  }),
                ),
                IconButton(
                  tooltip: 'Import TXT / CSV',
                  icon: const Icon(Icons.upload_file),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ImportScreen(services: widget.services),
                  )),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'export') _export();
                    if (v == 'share') shareShowcase(context, widget.services);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'export',
                      enabled: !_store.isEmpty,
                      child: const Text('Export CSV'),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      enabled: _store.countIn(Binder.showcase) > 0,
                      child: const Text('Share Showcase'),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(tabs: [
                Tab(text: 'All (${_store.totalCards})'),
                Tab(text: 'Showcase (${_store.countIn(Binder.showcase)})'),
                Tab(text: 'For trade (${_store.countIn(Binder.trade)})'),
              ]),
            ),
            body: TabBarView(children: [
              _list(_store.entries, null),
              _list(_store.inBinder(Binder.showcase), Binder.showcase),
              _list(_store.inBinder(Binder.trade), Binder.trade),
            ]),
          );
        },
      ),
    );
  }

  Widget _list(List<CollectionEntry> all, Binder? binder) {
    final entries = _query.isEmpty
        ? all
        : all.where((e) => e.card.name.toLowerCase().contains(_query) || e.card.setCode == _query).toList();
    if (all.isEmpty) {
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
                'Tap a card in All and move it here.',
          Binder.trade => 'Cards here are offered to friends first. Copies a Built deck needs are kept back.',
          _ => 'Scan cards, or import a TXT or CSV list from ManaBox, Moxfield, Deckbox or Archidekt.',
        },
      );
    }
    final value = entries.fold(0.0, (s, e) => s + (e.priceEur ?? 0) * e.quantity);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Text('${entries.fold(0, (s, e) => s + e.quantity)} cards'),
          const Spacer(),
          Text('≈ ${gbp(value)}', style: Theme.of(context).textTheme.titleSmall),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = entries[i];
            final c = e.card;
            final bits = [
              '${c.setCode.toUpperCase()}${c.collectorNumber.isEmpty ? '' : ' #${c.collectorNumber}'}',
              if (e.foil) 'foil',
              if (e.condition != CardCondition.nm) e.condition.code,
              if (binder == null && e.binder != Binder.collection) e.binder.label,
              if (e.priceEur != null) gbp(e.priceEur),
            ];
            return ListTile(
              leading: CardThumb(c.imageUrl),
              title: Text(c.name),
              subtitle: Text(bits.join(' · ')),
              trailing: Text('×${e.quantity}', style: Theme.of(context).textTheme.titleMedium),
              onTap: () => showEntrySheet(context, widget.services, e),
            );
          },
        ),
      ),
    ]);
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
