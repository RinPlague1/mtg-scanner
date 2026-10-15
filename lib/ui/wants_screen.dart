import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../services.dart';
import 'import_screen.dart';
import 'widgets.dart';

/// Your wants (deck gaps + wishlist) and your spares: what friends see.
class WantsScreen extends StatelessWidget {
  final AppServices services;
  const WantsScreen({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    final s = services;
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: Listenable.merge([s.collection, s.decks, s.wishlist, s.social]),
        builder: (context, _) {
          final wants = s.social.myWants;
          final spares = s.social.mySpares;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Wants & spares'),
              actions: [
                IconButton(
                  tooltip: 'Import a wishlist',
                  icon: const Icon(Icons.upload_file),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ImportScreen(services: s, initialTarget: ImportTarget.wishlist),
                  )),
                ),
              ],
              bottom: TabBar(tabs: [
                Tab(text: 'Wants (${wants.fold(0, (n, w) => n + w.qty)})'),
                Tab(text: 'Spares (${spares.fold(0, (n, c) => n + c.qty)})'),
              ]),
            ),
            floatingActionButton: FloatingActionButton(
              tooltip: 'Add to wishlist',
              onPressed: () => _addWish(context),
              child: const Icon(Icons.add),
            ),
            body: TabBarView(children: [
              wants.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border,
                      title: 'No wants',
                      body: 'Cards missing from your Built and Brewing decks show up here, '
                          'plus anything you add to your wishlist with +.',
                    )
                  : ListView(children: [
                      for (final w in wants)
                        ListTile(
                          dense: true,
                          leading: Icon(w.priority >= 3 ? Icons.priority_high : Icons.favorite_border,
                              color: w.priority >= 3 ? Colors.amber : null),
                          title: Text('${w.qty}× ${w.name}'),
                          subtitle: Text(w.reason),
                        ),
                      if (s.wishlist.items.isNotEmpty) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text('Manual wishlist', style: Theme.of(context).textTheme.titleSmall),
                        ),
                        for (final item in s.wishlist.items)
                          ListTile(
                            dense: true,
                            title: Text('${item.qty}× ${item.name}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => s.wishlist.remove(item),
                            ),
                          ),
                      ],
                    ]),
              spares.isEmpty
                  ? const EmptyState(
                      icon: Icons.swap_horiz,
                      title: 'No spares',
                      body: 'Cards in Up for trade, and collection copies no Built deck needs, are offered to '
                          'friends. Showcase cards never are.',
                    )
                  : ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Friends see these. Total ≈ ${gbp(spares.fold<double>(0.0, (n, c) => n + c.totalEur))}',
                        ),
                      ),
                      for (final c in spares) TradeCardTile(c),
                    ]),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _addWish(BuildContext context) async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (ctx) => _AddWishDialog(services: services),
    );
    if (result != null) await services.wishlist.add(result.$1, result.$2);
  }
}

class _AddWishDialog extends StatefulWidget {
  final AppServices services;
  const _AddWishDialog({required this.services});

  @override
  State<_AddWishDialog> createState() => _AddWishDialogState();
}

class _AddWishDialogState extends State<_AddWishDialog> {
  final _name = TextEditingController();
  int _qty = 1;
  List<String> _options = [];
  int _requestNo = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _lookup(String q) async {
    final n = ++_requestNo;
    try {
      final opts = await widget.services.scryfall.autocomplete(q);
      if (mounted && n == _requestNo) setState(() => _options = opts.take(6).toList());
    } catch (_) {
      // offline: free text still works
    }
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
          ),
          for (final o in _options)
            ListTile(
              dense: true,
              title: Text(o),
              onTap: () => setState(() {
                _name.text = o;
                _options = [];
              }),
            ),
          Row(children: [
            const Text('Copies'),
            const Spacer(),
            IconButton(
              onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_qty'),
            IconButton(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isNotEmpty) Navigator.pop(context, (n, _qty));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
