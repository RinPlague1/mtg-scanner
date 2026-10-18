import 'dart:async';

import 'package:flutter/material.dart';

import '../data/collection.dart';
import '../data/decks.dart';
import '../data/models.dart';
import '../data/scryfall.dart';
import '../services.dart';
import '../social/backend.dart';
import 'card_detail_sheet.dart';
import 'widgets.dart';

/// Add cards to a deck from a Scryfall search or from your collection.
class DeckAddCardsScreen extends StatefulWidget {
  final AppServices services;
  final String deckId;
  const DeckAddCardsScreen({super.key, required this.services, required this.deckId});

  @override
  State<DeckAddCardsScreen> createState() => _DeckAddCardsScreenState();
}

class _DeckAddCardsScreenState extends State<DeckAddCardsScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// Only show cards inside the commander's colour identity.
  bool _fitColours = true;

  // Scryfall results
  List<CardPrint> _results = [];
  bool _searching = false;
  String? _error;
  int _searchId = 0;

  AppServices get s => widget.services;
  Deck? get _deck => s.decks.byId(widget.deckId);

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      setState(() => _query = v.trim());
      _search();
    });
  }

  String? get _colourQuery {
    final cols = _deck?.commanderColours;
    if (!_fitColours || cols == null) return null;
    final c = cols.map((x) => x.toLowerCase()).join();
    return c.isEmpty ? 'id:c' : 'id<=$c';
  }

  Future<void> _search() async {
    final id = ++_searchId;
    if (_query.length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final q = [_query, ?_colourQuery, if (_deck?.format == 'commander') 'f:commander'].join(' ');
      final page = await s.scryfall.search(q, order: 'edhrec');
      if (id != _searchId || !mounted) return;
      setState(() => _results = page.cards);
    } catch (e) {
      if (id != _searchId || !mounted) return;
      setState(() => _error = errorText(e));
    } finally {
      if (id == _searchId && mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(CardPrint card) async {
    final d = _deck;
    if (d == null) return;
    final n = d.addCard(card);
    await s.decks.changed();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Text(n == 1 ? 'Added ${card.name}' : '${card.name}: now $n in the deck'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            d.setQty(nameKey(card.name), n - 1);
            s.decks.changed();
          },
        ),
      ));
  }

  bool _fits(CardPrint c) {
    final cols = _deck?.commanderColours;
    if (!_fitColours || cols == null || !c.hasDetails) return true;
    return c.colorIdentity.every(cols.contains);
  }

  @override
  Widget build(BuildContext context) {
    final d = _deck;
    if (d == null) return const Scaffold(body: Center(child: Text('Deck deleted')));
    final hasColours = d.commanderColours != null;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Add to ${d.name}'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Card name or Scryfall search',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onChanged,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        setState(() => _query = v.trim());
                        _search();
                      },
                    ),
                  ),
                  if (hasColours) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('In colours'),
                      selected: _fitColours,
                      onSelected: (v) {
                        setState(() => _fitColours = v);
                        _search();
                      },
                    ),
                  ],
                ]),
              ),
              const TabBar(tabs: [Tab(text: 'Scryfall'), Tab(text: 'My collection')]),
            ]),
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([s.decks, s.collection]),
          builder: (context, _) => TabBarView(children: [
            _scryfallTab(d),
            _collectionTab(d),
          ]),
        ),
      ),
    );
  }

  Widget _scryfallTab(Deck d) {
    if (_query.length < 2) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search for cards to add',
        body: 'Type a name, or Scryfall syntax like "t:shark" or "o:draw".',
      );
    }
    if (_searching && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    if (_results.isEmpty) return const EmptyState(icon: Icons.search_off, title: 'No cards found');
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) => _tile(d, _results[i]),
    );
  }

  Widget _collectionTab(Deck d) {
    final q = _query.toLowerCase();
    final seen = <String>{};
    final cards = <CollectionEntry>[];
    for (final e in s.collection.entries) {
      if (!seen.add(e.nameKey)) continue;
      if (q.isNotEmpty && !e.card.name.toLowerCase().contains(q)) continue;
      if (!_fits(e.card)) continue;
      cards.add(e);
    }
    cards.sort((a, b) => a.card.name.compareTo(b.card.name));
    if (cards.isEmpty) {
      return EmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: s.collection.isEmpty ? 'Your collection is empty' : 'Nothing in your collection matches',
      );
    }
    return ListView.builder(
      itemCount: cards.length,
      itemBuilder: (context, i) => _tile(d, cards[i].card, owned: s.collection.ownedCount(cards[i].nameKey)),
    );
  }

  Widget _tile(Deck d, CardPrint c, {int? owned}) {
    final inDeck = d.byKey(nameKey(c.name))?.qty ?? 0;
    final have = owned ?? s.collection.ownedCount(nameKey(c.name));
    return ListTile(
      dense: true,
      leading: CardThumb(c.imageUrl, width: 32),
      title: Text(c.name),
      subtitle: Text(
        [
          if (c.typeLine.isNotEmpty) c.typeLine,
          if (have > 0) 'own $have',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => showCardDetail(context, s, c, forDeckId: d.id),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ManaCost(c.manaCost),
        if (inDeck > 0) Padding(padding: const EdgeInsets.only(left: 6), child: Text('×$inDeck')),
        IconButton(
          tooltip: 'Add to deck',
          icon: Icon(inDeck > 0 ? Icons.add_circle : Icons.add_circle_outline),
          onPressed: () => _add(c),
        ),
      ]),
    );
  }
}
