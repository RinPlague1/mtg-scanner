import 'package:flutter/material.dart';

import '../data/collection_stats.dart';
import '../data/prices.dart';
import '../services.dart';
import '../social/backend.dart';
import 'widgets.dart';

/// Collection value (with change since the last price refresh), duplicates
/// and set completion.
class CollectionInsightsScreen extends StatefulWidget {
  final AppServices services;
  const CollectionInsightsScreen({super.key, required this.services});

  @override
  State<CollectionInsightsScreen> createState() => _CollectionInsightsScreenState();
}

class _CollectionInsightsScreenState extends State<CollectionInsightsScreen> {
  String? _progress;
  bool _commander = true;
  Future<Map<String, ({String name, int count})>>? _sets;

  AppServices get s => widget.services;

  Future<void> _refreshPrices() async {
    final before = s.collection.totalEur;
    setState(() => _progress = 'Updating prices…');
    try {
      final n = await s.collection.refreshPrices(s.scryfall, onProgress: (done, total) {
        if (mounted) setState(() => _progress = 'Updating prices… $done of $total');
      });
      // Remember the value before this refresh so the change can be shown.
      await s.settings.setValueSnapshot(before);
      if (mounted) showMessage(context, 'Updated prices for $n cards');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: ListenableBuilder(
        listenable: Listenable.merge([s.collection, s.settings, Fx.instance]),
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Collection insights'),
            actions: [
              IconButton(
                tooltip: 'Update prices',
                icon: _progress != null
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.price_change_outlined),
                onPressed: _progress != null ? null : _refreshPrices,
              ),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Value'), Tab(text: 'Duplicates'), Tab(text: 'Sets')]),
          ),
          body: TabBarView(children: [_value(), _duplicates(), _setsTab()]),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _row(ValueRow r, double total) => ListTile(
        dense: true,
        title: Text(r.label),
        subtitle: LinearProgressIndicator(value: total <= 0 ? 0 : (r.eur / total).clamp(0, 1)),
        trailing: Text('${gbp(r.eur)} · ${r.cards}'),
      );

  Widget _value() {
    final entries = s.collection.entries;
    final total = s.collection.totalEur;
    final st = s.settings;
    final change = st.lastValueEur == null ? null : total - st.lastValueEur!;
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(gbp(total), style: theme.textTheme.headlineMedium),
          Text('${s.collection.totalCards} cards (Cardmarket prices)'),
          if (change != null && st.lastValueAt != null)
            Text(
              '${change >= 0 ? '▲' : '▼'} ${gbp(change.abs())} since before the last price update '
              '(${st.lastValueAt!.day}/${st.lastValueAt!.month})',
              style: TextStyle(color: change >= 0 ? Colors.greenAccent : theme.colorScheme.error),
            )
          else
            Text('Tap ⟳ (top right) to update prices and start tracking changes.', style: theme.textTheme.bodySmall),
          if (_progress != null) Text(_progress!, style: theme.textTheme.bodySmall),
        ]),
      ),
      _section('By binder'),
      for (final r in valueByBinder(entries)) _row(r, total),
      if (entries.any((e) => e.folder != null)) ...[
        _section('By folder'),
        for (final r in valueByFolder(entries)) _row(r, total),
      ],
      _section('Top sets'),
      for (final r in valueBySet(entries).take(10)) _row(r, total),
      _section('Most valuable cards'),
      for (final e in mostValuable(entries))
        ListTile(
          dense: true,
          leading: CardThumb(e.card.imageUrl, width: 32),
          title: Text(e.card.name),
          subtitle: Text('${e.card.setCode.toUpperCase()}${e.foil ? ' · foil' : ''} · ${e.binder.label}'
              '${e.quantity > 1 ? ' · ×${e.quantity}' : ''}'),
          trailing: Text(gbp(e.priceEur)),
        ),
    ]);
  }

  Widget _duplicates() {
    final keep = _commander ? 1 : 4;
    final dups = duplicates(s.collection.entries, keep: keep);
    final extraValue = dups.fold<double>(0, (sum, d) {
      final each = d.entries.map((e) => e.priceEur ?? 0).fold<double>(0, (m, v) => v > m ? v : m);
      return sum + each * d.extra;
    });
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Keep 1 (Commander)')),
              ButtonSegment(value: false, label: Text('Keep 4')),
            ],
            selected: {_commander},
            onSelectionChanged: (v) => setState(() => _commander = v.first),
          ),
          const SizedBox(height: 8),
          Text(dups.isEmpty
              ? 'No extras beyond $keep of each card (basic lands ignored).'
              : '${dups.fold(0, (n, d) => n + d.extra)} extra copies across ${dups.length} cards, up to ≈ ${gbp(extraValue)}. '
                  'Good trade bait: move them to Up for trade.'),
        ]),
      ),
      for (final d in dups)
        ListTile(
          dense: true,
          leading: CardThumb(d.entries.first.card.imageUrl, width: 32),
          title: Text(d.name),
          subtitle: Text('${d.copies} owned · ${d.entries.map((e) => e.binder.label).toSet().join(', ')}'),
          trailing: Text('+${d.extra}', style: Theme.of(context).textTheme.titleMedium),
        ),
    ]);
  }

  Widget _setsTab() {
    _sets ??= s.scryfall.sets();
    return FutureBuilder<Map<String, ({String name, int count})>>(
      future: _sets,
      builder: (context, snap) {
        final sizes = snap.data ?? const <String, ({String name, int count})>{};
        final rows = setProgress(s.collection.entries, sizes);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (snap.hasError)
            ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text("Couldn't load set sizes, so only counts are shown"),
              trailing: TextButton(onPressed: () => setState(() => _sets = s.scryfall.sets()), child: const Text('Retry')),
            ),
          if (!snap.hasData && !snap.hasError) const LinearProgressIndicator(),
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text('${r.name} (${r.code.toUpperCase()})'),
              subtitle: r.total > 0 ? LinearProgressIndicator(value: r.fraction) : null,
              trailing: Text(r.total > 0 ? '${r.owned}/${r.total} · ${(r.fraction * 100).round()}%' : '${r.owned}'),
            ),
        ]);
      },
    );
  }
}
