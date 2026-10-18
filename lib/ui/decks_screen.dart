import 'package:flutter/material.dart';

import '../data/decks.dart';
import '../data/models.dart';
import '../services.dart';
import 'deck_screen.dart';
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
            icon: const Icon(Icons.add),
            label: const Text('New deck'),
            onPressed: () => _newDeck(context),
          ),
          body: decks.isEmpty
              ? const EmptyState(
                  icon: Icons.layers_outlined,
                  title: 'No decks yet',
                  body: 'Build a deck from scratch, or import a decklist (TXT or CSV from Moxfield, '
                      'Archidekt or Arena). Cards missing from Built and Brewing decks become trade wants automatically.',
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
      leading: d.commanders.isNotEmpty && d.commanders.first.card?.imageUrl != null
          ? CardThumb(d.commanders.first.card!.imageUrl, width: 32)
          : const Icon(Icons.layers),
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

  Future<void> _newDeck(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Build from scratch'),
            subtitle: const Text('Start empty and add cards from Scryfall or your collection'),
            onTap: () => Navigator.pop(ctx, 'empty'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import a decklist'),
            subtitle: const Text('TXT or CSV from Moxfield, Archidekt or Arena'),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'import') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImportScreen(services: services, initialTarget: ImportTarget.deck),
      ));
      return;
    }
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New deck'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Deck name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    // New decks start as Brewing, so nothing is reserved until you mark it Built.
    final deck = Deck(name: name.isEmpty ? 'New deck' : name, status: DeckStatus.brewing);
    await services.decks.add(deck);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeckDetailScreen(services: services, deckId: deck.id),
    ));
  }
}
