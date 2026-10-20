import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../data/scryfall.dart';
import '../data/wishlist.dart';
import '../services.dart';
import '../social/backend.dart';
import 'import_screen.dart';
import 'printing_picker.dart';
import 'widgets.dart';

/// Your wishlist: exact printing or any, foil or not, priority, and price
/// alerts when a card drops to your price.
class WishlistScreen extends StatefulWidget {
  final AppServices services;
  const WishlistScreen({super.key, required this.services});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _checking = false;

  WishlistStore get _store => widget.services.wishlist;

  @override
  void initState() {
    super.initState();
    // Prices are checked at most twice a day when the list is opened.
    final stale = _store.items.any((w) =>
        w.checkedAt == null || DateTime.now().difference(w.checkedAt!) > const Duration(hours: 12));
    if (stale) WidgetsBinding.instance.addPostFrameCallback((_) => _check(quiet: true));
  }

  Future<void> _check({bool quiet = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await _store.checkPrices(widget.services.scryfall);
      if (!quiet && mounted) showMessage(context, 'Prices updated');
    } catch (e) {
      if (!quiet && mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, Fx.instance, widget.services.collection]),
      builder: (context, _) {
        final items = [..._store.items]..sort((a, b) {
            if (a.priority != b.priority) return b.priority.value.compareTo(a.priority.value);
            return a.name.compareTo(b.name);
          });
        final alerts = _store.alerts(Fx.instance.gbp).toSet();
        return Scaffold(
          appBar: AppBar(
            title: Text('Wishlist · ${items.length}'),
            actions: [
              IconButton(
                tooltip: 'Check prices',
                icon: _checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.price_check),
                onPressed: _checking ? null : _check,
              ),
              IconButton(
                tooltip: 'Import a wishlist',
                icon: const Icon(Icons.upload_file),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ImportScreen(services: widget.services, initialTarget: ImportTarget.wishlist),
                )),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Add card'),
            onPressed: () => showWishEditor(context, widget.services),
          ),
          body: items.isEmpty
              ? const EmptyState(
                  icon: Icons.favorite_border,
                  title: 'Your wishlist is empty',
                  body: 'Add cards here, or tap the heart on any card. Set a price to be told when it drops. '
                      'Friends see your wishlist in your wants.',
                )
              : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                  if (alerts.isNotEmpty)
                    MaterialBanner(
                      leading: const Icon(Icons.notifications_active, color: Colors.amber),
                      content: Text('${alerts.length} card${alerts.length == 1 ? ' is' : 's are'} at or under your price'),
                      actions: const [SizedBox()],
                    ),
                  for (final w in items) _tile(w, alerts.contains(w)),
                ]),
        );
      },
    );
  }

  Widget _tile(WishItem w, bool alert) {
    final owned = widget.services.collection.ownedCount(w.key);
    final price = w.lastEur == null ? null : gbp(w.lastEur);
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CardThumb(w.card?.imageUrl, width: 36),
      title: Text('${w.qty}× ${w.name}'),
      subtitle: Text([
        if (w.details.isNotEmpty) w.details,
        if (price != null) 'now $price',
        if (w.maxGbp != null) 'alert ≤ £${w.maxGbp!.toStringAsFixed(2)}',
        if (owned > 0) 'you own $owned',
      ].join(' · ')),
      trailing: alert
          ? const Icon(Icons.notifications_active, color: Colors.amber)
          : Icon(
              switch (w.priority) {
                WishPriority.mustHave => Icons.priority_high,
                WishPriority.want => Icons.favorite,
                WishPriority.niceToHave => Icons.favorite_border,
              },
              color: w.priority == WishPriority.mustHave ? cs.error : null,
            ),
      onTap: () => showWishEditor(context, widget.services, existing: w),
    );
  }
}

/// Add or edit a wish. With no [name]/[existing], asks for a card name first.
/// [printing] (e.g. from a card's details) is offered as "this printing".
Future<void> showWishEditor(BuildContext context, AppServices services,
    {WishItem? existing, String? name, CardPrint? printing}) async {
  var cardName = existing?.name ?? name;
  cardName ??= await showDialog<String>(context: context, builder: (_) => _NameDialog(services: services));
  if (cardName == null || cardName.trim().isEmpty || !context.mounted) return;
  final item = existing ?? services.wishlist.byName(cardName) ?? WishItem(cardName.trim());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WishEditor(services: services, item: item, printing: printing, isNew: !services.wishlist.contains(item.name)),
  );
}

class _WishEditor extends StatefulWidget {
  final AppServices services;
  final WishItem item;
  final CardPrint? printing;
  final bool isNew;
  const _WishEditor({required this.services, required this.item, required this.printing, required this.isNew});

  @override
  State<_WishEditor> createState() => _WishEditorState();
}

class _WishEditorState extends State<_WishEditor> {
  late int _qty = widget.item.qty;
  late WishPriority _priority = widget.item.priority;
  late CardPrint? _card = widget.item.card;
  late bool? _foil = widget.item.foil;
  late final _max = TextEditingController(text: widget.item.maxGbp?.toStringAsFixed(2) ?? '');

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  Future<void> _choosePrinting() async {
    final s = widget.services;
    try {
      final base = _card ?? widget.printing ?? await s.scryfall.named(widget.item.name);
      if (base == null || !mounted) return;
      final p = await pickPrinting(context, s.scryfall, base);
      if (p != null) setState(() => _card = p);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _save() async {
    final w = widget.item
      ..qty = _qty
      ..priority = _priority
      ..card = _card
      ..foil = _foil
      ..maxGbp = double.tryParse(_max.text.replaceAll('£', '').trim());
    // Price for what's now wanted (from the card we have, if any).
    if (_card != null) w.lastEur = w.priceOf(_card!);
    await widget.services.wishlist.put(w);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.printing;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.item.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Copies wanted'),
            const Spacer(),
            IconButton(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
            Text('$_qty', style: theme.textTheme.titleMedium),
            IconButton(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
          ]),
          const Text('Priority'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final pr in WishPriority.values.reversed)
              ChoiceChip(label: Text(pr.label), selected: _priority == pr, onSelected: (_) => setState(() => _priority = pr)),
          ]),
          const SizedBox(height: 12),
          const Text('Printing'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            ChoiceChip(label: const Text('Any'), selected: _card == null, onSelected: (_) => setState(() => _card = null)),
            if (p != null && _card?.id != p.id)
              ChoiceChip(
                label: Text('This one (${p.setCode.toUpperCase()} #${p.collectorNumber})'),
                selected: false,
                onSelected: (_) => setState(() => _card = p),
              ),
            if (_card != null)
              ChoiceChip(
                avatar: CardThumb(_card!.imageUrl, width: 18),
                label: Text('${_card!.setName} #${_card!.collectorNumber}'),
                selected: true,
                onSelected: (_) {},
              ),
            ActionChip(avatar: const Icon(Icons.swap_horiz, size: 16), label: const Text('Choose…'), onPressed: _choosePrinting),
          ]),
          const SizedBox(height: 12),
          const Text('Finish'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            ChoiceChip(label: const Text('Either'), selected: _foil == null, onSelected: (_) => setState(() => _foil = null)),
            ChoiceChip(label: const Text('Non-foil'), selected: _foil == false, onSelected: (_) => setState(() => _foil = false)),
            ChoiceChip(label: const Text('Foil'), selected: _foil == true, onSelected: (_) => setState(() => _foil = true)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Price alert (optional)',
              prefixText: '£ ',
              helperText: 'Highlighted when the price is at or under this',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            if (!widget.isNew)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
                onPressed: () async {
                  await widget.services.wishlist.remove(widget.item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            const Spacer(),
            FilledButton(onPressed: _save, child: Text(widget.isNew ? 'Add to wishlist' : 'Save')),
          ]),
        ]),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final AppServices services;
  const _NameDialog({required this.services});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();
  List<String> _options = [];
  int _req = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _lookup(String q) async {
    final n = ++_req;
    try {
      final opts = await widget.services.scryfall.autocomplete(q);
      if (mounted && n == _req) setState(() => _options = opts.take(6).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to wishlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Card name'),
            onChanged: _lookup,
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          for (final o in _options) ListTile(dense: true, title: Text(o), onTap: () => Navigator.pop(context, o)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text.trim()), child: const Text('Next')),
      ],
    );
  }
}
