import 'package:flutter/material.dart';

import '../data/decks.dart';
import '../data/models.dart';
import '../services.dart';
import 'import_screen.dart';
import 'wants_screen.dart';
import 'widgets.dart';

class DecksScreen extends StatelessWidget {
  final AppServices services;
  const DecksScreen({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    final s = services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.decks, s.collection]),
      builder: (context, _) {
        final decks = s.decks.decks;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Decks'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.favorite_border),
                label: const Text('Wants'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WantsScreen(services: s),
                )),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.upload_file),
            label: const Text('Import deck'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImportScreen(services: s, initialTarget: ImportTarget.deck),
            )),
          ),
          body: decks.isEmpty
              ? const EmptyState(
                  icon: Icons.layers_outlined,
                  title: 'No decks yet',
                  body: 'Import a decklist (TXT or CSV from Moxfield, Archidekt or Arena). '
                      'Cards missing from Built and Brewing decks become trade wants automatically.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final st in DeckStatus.values)
                      if (decks.any((d) => d.status == st)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(st.label, style: Theme.of(context).textTheme.titleSmall),
                        ),
                        for (final d in decks.where((d) => d.status == st)) _deckTile(context, d),
                      ],
                  ],
                ),
        );
      },
    );
  }

  Widget _deckTile(BuildContext context, Deck d) {
    final missing = d.needs.entries.fold(0, (n, e) {
      final have = services.collection.ownedCount(e.key);
      return n + (e.value > have ? e.value - have : 0);
    });
    final commanders = d.commanders.map((c) => c.name).join(' & ');
    return ListTile(
      leading: const Icon(Icons.layers),
      title: Text(d.name),
      subtitle: Text([
        if (commanders.isNotEmpty) commanders,
        '${d.cardCount} cards',
        if (d.status != DeckStatus.retired) missing == 0 ? 'complete' : '$missing missing',
      ].join(' · ')),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DeckDetailScreen(services: services, deckId: d.id),
      )),
    );
  }
}

class DeckDetailScreen extends StatelessWidget {
  final AppServices services;
  final String deckId;
  const DeckDetailScreen({super.key, required this.services, required this.deckId});

  @override
  Widget build(BuildContext context) {
    final s = services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.decks, s.collection]),
      builder: (context, _) {
        final d = s.decks.byId(deckId);
        if (d == null) return const Scaffold(body: Center(child: Text('Deck deleted')));
        final rows = d.cards.map((c) => (card: c, have: s.collection.ownedCount(c.key))).toList()
          ..sort((a, b) {
            final am = a.have < a.card.qty, bm = b.have < b.card.qty;
            if (a.card.commander != b.card.commander) return a.card.commander ? -1 : 1;
            if (am != bm) return am ? -1 : 1;
            return a.card.name.compareTo(b.card.name);
          });
        final missing = rows.fold(0, (n, r) => n + (r.card.qty > r.have ? r.card.qty - r.have : 0));
        return Scaffold(
          appBar: AppBar(
            title: Text(d.name),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit),
                onPressed: () => _rename(context, d),
              ),
              IconButton(
                tooltip: 'Delete deck',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, d),
              ),
            ],
          ),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<DeckStatus>(
                  segments: [
                    for (final st in DeckStatus.values) ButtonSegment(value: st, label: Text(st.label)),
                  ],
                  selected: {d.status},
                  onSelectionChanged: (v) {
                    d.status = v.first;
                    s.decks.changed();
                  },
                ),
                const SizedBox(height: 8),
                Text(switch (d.status) {
                  DeckStatus.built => missing == 0
                      ? 'You own every card. These copies are kept out of trades.'
                      : '$missing cards missing, and they are on your trade wants (top priority). '
                          'Owned copies are kept out of trades.',
                  DeckStatus.brewing => missing == 0
                      ? 'You own every card.'
                      : '$missing cards missing, and they are on your trade wants.',
                  DeckStatus.retired => 'Retired: nothing is reserved, and spare copies can be traded.',
                }),
              ]),
            ),
            const Divider(height: 1),
            for (final r in rows)
              ListTile(
                dense: true,
                leading: r.card.commander
                    ? const Icon(Icons.star, color: Colors.amber)
                    : Icon(
                        r.have >= r.card.qty ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: r.have >= r.card.qty ? Colors.greenAccent : null,
                      ),
                title: Text('${r.card.qty}× ${r.card.name}'),
                trailing: r.have >= r.card.qty
                    ? null
                    : Text(r.have == 0 ? 'missing' : 'own ${r.have}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, Deck d) async {
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
      await services.decks.changed();
    }
  }

  Future<void> _delete(BuildContext context, Deck d) async {
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
      await services.decks.remove(d);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
