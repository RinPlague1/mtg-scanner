import 'package:flutter/material.dart';

import '../data/collection.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/scan_buffer.dart';
import '../data/scryfall.dart';
import 'widgets.dart';

/// Review scanned cards: fix the printing, foil, condition and quantity, choose
/// a binder for each, then add them to the collection.
class ScanReviewScreen extends StatefulWidget {
  final ScanBuffer buffer;
  final CollectionStore collection;
  final ScryfallClient scryfall;
  const ScanReviewScreen({super.key, required this.buffer, required this.collection, required this.scryfall});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  /// Ids of ticked rows. Empty = act on everything.
  final Set<String> _selected = {};
  bool _busy = false;

  ScanBuffer get _buffer => widget.buffer;

  List<BufferItem> get _targets =>
      _selected.isEmpty ? _buffer.items : _buffer.items.where((i) => _selected.contains(i.id)).toList();

  Future<void> _commit() async {
    final targets = _targets;
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    final byBinder = <Binder, int>{};
    for (final i in targets) {
      byBinder.update(i.binder, (n) => n + i.quantity, ifAbsent: () => i.quantity);
    }
    final added = await _buffer.commit(widget.collection, targets);
    _selected.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    final where = byBinder.entries.map((e) => '${e.value} to ${e.key.label}').join(', ');
    showMessage(context, 'Added $added cards: $where');
    if (_buffer.isEmpty) Navigator.pop(context);
  }

  Future<void> _setForTargets({Binder? binder, CardCondition? condition, bool? foil}) async {
    if (_selected.isEmpty) {
      await _buffer.setAll(binder: binder, condition: condition, foil: foil);
      return;
    }
    for (final i in _targets) {
      if (binder != null) i.binder = binder;
      if (condition != null) i.condition = condition;
      if (foil != null) i.foil = foil;
    }
    await _buffer.changed();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the scan list?'),
        content: Text('${_buffer.count} scanned cards will be discarded. Nothing is added to your collection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await _buffer.clear();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_buffer, Fx.instance]),
      builder: (context, _) {
        _selected.removeWhere((id) => !_buffer.items.any((i) => i.id == id));
        final items = _buffer.items;
        final targets = _targets;
        final targetCount = targets.fold(0, (n, i) => n + i.quantity);
        final scope = _selected.isEmpty ? 'all' : '${_selected.length} selected';
        return Scaffold(
          appBar: AppBar(
            title: Text('Scan list · ${_buffer.count}'),
            actions: [
              if (_selected.isNotEmpty)
                TextButton(onPressed: () => setState(_selected.clear), child: const Text('Deselect')),
              IconButton(
                tooltip: 'Clear list',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: items.isEmpty ? null : _clear,
              ),
            ],
          ),
          bottomNavigationBar: items.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.library_add_check),
                      label: Text(_selected.isEmpty
                          ? 'Add all $targetCount to collection'
                          : 'Add $targetCount selected to collection'),
                      onPressed: _busy ? null : _commit,
                    ),
                  ),
                ),
          body: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox,
                  title: 'Nothing scanned yet',
                  body: 'Scanned cards wait here so you can check them and choose where they go.',
                )
              : ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                  // Bulk actions for everything, or for the ticked rows.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Set $scope to', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      for (final b in Binder.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ActionChip(
                            avatar: Icon(_binderIcon(b), size: 18),
                            label: Text(b.label),
                            onPressed: () => _setForTargets(binder: b),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: PopupMenuButton<CardCondition>(
                          onSelected: (c) => _setForTargets(condition: c),
                          itemBuilder: (_) => [
                            for (final c in CardCondition.values) PopupMenuItem(value: c, child: Text(c.label)),
                          ],
                          child: const Chip(avatar: Icon(Icons.grade_outlined, size: 18), label: Text('Condition')),
                        ),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Total ≈ ${gbp(_buffer.totalEur)}. Tick cards to change just those.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Divider(),
                  for (final i in items) _row(context, i),
                ]),
        );
      },
    );
  }

  IconData _binderIcon(Binder b) => switch (b) {
        Binder.collection => Icons.collections_bookmark_outlined,
        Binder.showcase => Icons.auto_awesome,
        Binder.trade => Icons.swap_horiz,
      };

  Widget _row(BuildContext context, BufferItem i) {
    final theme = Theme.of(context);
    final ticked = _selected.contains(i.id);
    return Dismissible(
      key: ValueKey(i.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => _buffer.remove(i),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: ticked,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(i.id);
              } else {
                _selected.remove(i.id);
              }
            }),
          ),
          GestureDetector(onTap: () => _pickPrinting(i), child: CardThumb(i.card.imageUrl, width: 56)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.card.name, style: theme.textTheme.titleSmall),
              InkWell(
                onTap: () => _pickPrinting(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Flexible(
                      child: Text(
                        '${i.card.setCode.toUpperCase()} #${i.card.collectorNumber}'
                        '${i.priceEur != null ? ' · ${gbp(i.priceEur)}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      i.exactPrinting ? Icons.edit_outlined : Icons.help_outline,
                      size: 14,
                      color: i.exactPrinting ? theme.colorScheme.outline : Colors.amber,
                    ),
                    if (!i.exactPrinting)
                      Text(' check printing', style: theme.textTheme.labelSmall?.copyWith(color: Colors.amber)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _binderMenu(i),
                PopupMenuButton<CardCondition>(
                  initialValue: i.condition,
                  onSelected: (c) {
                    i.condition = c;
                    _buffer.changed();
                  },
                  itemBuilder: (_) => [
                    for (final c in CardCondition.values) PopupMenuItem(value: c, child: Text(c.label)),
                  ],
                  child: Chip(label: Text(i.condition.code), visualDensity: VisualDensity.compact),
                ),
                FilterChip(
                  label: const Text('Foil'),
                  selected: i.foil,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) {
                    i.foil = v;
                    _buffer.changed();
                  },
                ),
              ]),
            ]),
          ),
          Column(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: () {
                i.quantity++;
                _buffer.changed();
              },
            ),
            Text('×${i.quantity}', style: theme.textTheme.titleSmall),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(i.quantity > 1 ? Icons.remove : Icons.delete_outline),
              onPressed: () {
                if (i.quantity > 1) {
                  i.quantity--;
                  _buffer.changed();
                } else {
                  _buffer.remove(i);
                }
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _binderMenu(BufferItem i) => PopupMenuButton<Binder>(
        initialValue: i.binder,
        onSelected: (b) {
          i.binder = b;
          _buffer.changed();
        },
        itemBuilder: (_) => [
          for (final b in Binder.values)
            PopupMenuItem(
              value: b,
              child: Row(children: [Icon(_binderIcon(b), size: 18), const SizedBox(width: 8), Text(b.label)]),
            ),
        ],
        child: Chip(
          avatar: Icon(_binderIcon(i.binder), size: 16),
          label: Text(i.binder.label),
          visualDensity: VisualDensity.compact,
        ),
      );

  Future<void> _pickPrinting(BufferItem item) async {
    final picked = await showModalBottomSheet<CardPrint>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => FutureBuilder<List<CardPrint>>(
          future: widget.scryfall.printings(item.card.name),
          builder: (ctx, snap) {
            if (snap.hasError) return Center(child: Text('Could not load printings: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            return ListView.builder(
              controller: scroll,
              itemCount: list.length,
              itemBuilder: (ctx, n) {
                final p = list[n];
                return ListTile(
                  selected: p.id == item.card.id,
                  leading: CardThumb(p.imageUrl),
                  title: Text('${p.setName} (${p.setCode.toUpperCase()})'),
                  subtitle: Text('#${p.collectorNumber} · ${p.rarity}'),
                  trailing: Text(gbp(double.tryParse(p.priceEur ?? ''))),
                  onTap: () => Navigator.of(ctx).pop(p),
                );
              },
            );
          },
        ),
      ),
    );
    if (picked != null) {
      item.card = picked;
      item.exactPrinting = true;
      await _buffer.changed();
    }
  }
}
