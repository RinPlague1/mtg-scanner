import 'package:flutter/material.dart';

import '../data/decks.dart';
import '../data/collection_query.dart' show cardTypes, rarities;
import '../data/models.dart';
import '../data/scryfall.dart';
import '../data/search_filters.dart';
import '../data/suggestions.dart';
import '../services.dart';
import '../social/backend.dart';
import 'card_detail_sheet.dart';
import 'collection_tools.dart' show colourNames;
import 'widgets.dart';

/// Search Scryfall, and browse card suggestions for imported decks.
class SearchScreen extends StatelessWidget {
  final AppServices services;
  const SearchScreen({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Search'),
          bottom: const TabBar(tabs: [Tab(text: 'Scryfall'), Tab(text: 'For your decks')]),
        ),
        body: TabBarView(children: [
          _ScryfallSearch(services: services),
          _DeckSuggestions(services: services),
        ]),
      ),
    );
  }
}

/// Paged results for one Scryfall query, loaded as you scroll.
class _ResultPager {
  final ScryfallClient scryfall;
  final String query;
  final String order;
  final List<CardPrint> cards = [];
  int page = 0;
  bool hasMore = true;
  bool loading = false;
  int total = 0;
  String? error;

  _ResultPager(this.scryfall, this.query, {this.order = 'name'});

  Future<void> next(VoidCallback changed) async {
    if (loading || !hasMore) return;
    loading = true;
    changed();
    try {
      final p = await scryfall.search(query, page: page + 1, order: order);
      page++;
      cards.addAll(p.cards);
      hasMore = p.hasMore;
      total = p.total;
    } catch (e) {
      error = _searchError(e);
      hasMore = false;
    } finally {
      loading = false;
      changed();
    }
  }
}

String _searchError(Object e) {
  final s = e.toString();
  // Scryfall explains bad syntax in the "details" field of a 400/422 reply.
  final m = RegExp(r'"details"\s*:\s*"([^"]+)"').firstMatch(s);
  if (m != null) return m.group(1)!;
  return errorText(e);
}

/// Grid of card images with "owned" / "in deck" markers.
class _CardGrid extends StatelessWidget {
  final AppServices services;
  final List<CardPrint> cards;
  final bool loading;
  final bool hasMore;
  final VoidCallback onMore;
  final String? forDeckId;
  final Widget? header;
  const _CardGrid({
    required this.services,
    required this.cards,
    required this.loading,
    required this.hasMore,
    required this.onMore,
    this.forDeckId,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    // Filters can leave too few cards to scroll; keep loading until the
    // screen fills or Scryfall runs out.
    if (hasMore && !loading && cards.length < 18) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onMore());
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (hasMore && !loading && n.metrics.pixels > n.metrics.maxScrollExtent - 600) onMore();
        return false;
      },
      child: CustomScrollView(slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.66,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final c = cards[i];
                final owned = services.collection.ownedCount(nameKey(c.name));
                return GestureDetector(
                  onTap: () => showCardDetail(context, services, c, forDeckId: forDeckId),
                  child: Stack(children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: c.imageUrl == null
                            ? Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(6),
                                child: Text(c.name, textAlign: TextAlign.center),
                              )
                            : Image.network(c.imageUrl!, fit: BoxFit.cover),
                      ),
                    ),
                    if (owned > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration:
                              BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(10)),
                          child: Text('owned ×$owned', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                  ]),
                );
              },
              childCount: cards.length,
            ),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          ),
      ]),
    );
  }
}

List<CardPrint> _applyOwned(AppServices s, List<CardPrint> cards, OwnedFilter f) => switch (f) {
      OwnedFilter.any => cards,
      OwnedFilter.owned => cards.where((c) => s.collection.ownedCount(nameKey(c.name)) > 0).toList(),
      OwnedFilter.notOwned => cards.where((c) => s.collection.ownedCount(nameKey(c.name)) == 0).toList(),
    };

Widget _filterButton(SearchFilters f, VoidCallback onPressed) => IconButton(
      tooltip: 'Filter',
      icon: Badge(isLabelVisible: f.count > 0, label: Text('${f.count}'), child: const Icon(Icons.filter_list)),
      onPressed: onPressed,
    );

Future<SearchFilters?> showSearchFilters(BuildContext context, SearchFilters f, {bool showColours = true}) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SearchFilterSheet(initial: f, showColours: showColours),
  );
}

class _SearchFilterSheet extends StatefulWidget {
  final SearchFilters initial;
  final bool showColours;
  const _SearchFilterSheet({required this.initial, required this.showColours});

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late SearchFilters f = widget.initial;

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  Widget _section(String title, List<Widget> chips, {String? note}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (note != null) Text(note, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: chips),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
            Text('Filter', style: Theme.of(context).textTheme.titleLarge),
            if (widget.showColours)
              _section('Colour identity', note: 'Cards that fit within the colours you pick', [
                for (final c in ['W', 'U', 'B', 'R', 'G', 'C'])
                  FilterChip(
                    label: Text(colourNames[c]!),
                    selected: f.colours.contains(c),
                    onSelected: (_) => setState(() => f = f.copyWith(colours: _toggle(f.colours, c))),
                  ),
              ]),
            _section('Type', [
              for (final t in cardTypes)
                FilterChip(
                  label: Text(t),
                  selected: f.types.contains(t),
                  onSelected: (_) => setState(() => f = f.copyWith(types: _toggle(f.types, t))),
                ),
            ]),
            _section('Mana value', [
              for (var v = 0; v <= 7; v++)
                FilterChip(
                  label: Text(v == 7 ? '7+' : '$v'),
                  selected: f.manaValues.contains(v),
                  onSelected: (_) => setState(() => f = f.copyWith(manaValues: _toggle(f.manaValues, v))),
                ),
            ]),
            _section('Rarity', [
              for (final r in rarities)
                FilterChip(
                  label: Text(r[0].toUpperCase() + r.substring(1)),
                  selected: f.rarities.contains(r),
                  onSelected: (_) => setState(() => f = f.copyWith(rarities: _toggle(f.rarities, r))),
                ),
            ]),
            _section('Your collection', [
              for (final o in OwnedFilter.values)
                ChoiceChip(
                  label: Text(switch (o) {
                    OwnedFilter.any => 'Any',
                    OwnedFilter.owned => 'Owned',
                    OwnedFilter.notOwned => 'Not owned',
                  }),
                  selected: f.owned == o,
                  onSelected: (_) => setState(() => f = f.copyWith(owned: o)),
                ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Commander legal only'),
              value: f.commanderLegal,
              onChanged: (v) => setState(() => f = f.copyWith(commanderLegal: v)),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              TextButton(
                onPressed: f.isEmpty ? null : () => setState(() => f = const SearchFilters()),
                child: const Text('Clear all'),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Apply')),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Scryfall search ─────────────────────────

class _ScryfallSearch extends StatefulWidget {
  final AppServices services;
  const _ScryfallSearch({required this.services});

  @override
  State<_ScryfallSearch> createState() => _ScryfallSearchState();
}

class _ScryfallSearchState extends State<_ScryfallSearch> with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  _ResultPager? _pager;
  String _order = 'name';
  SearchFilters _filters = const SearchFilters();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _run() {
    final q = combineQuery(_text.text, _filters.toQuery());
    if (q.isEmpty) {
      // Only "owned" set, or nothing at all: need something to search for.
      if (_text.text.trim().isEmpty && !_filters.isEmpty) {
        showMessage(context, 'Type a name too, or pick a colour, type or mana value');
      }
      return;
    }
    FocusScope.of(context).unfocus();
    final p = _ResultPager(widget.services.scryfall, q, order: _order);
    setState(() => _pager = p);
    p.next(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = _pager;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Card name, or Scryfall syntax like t:shark c:u',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _text.clear();
                    _pager = null;
                  }),
                ),
              ),
              onSubmitted: (_) => _run(),
            ),
          ),
          _filterButton(_filters, () async {
            final f = await showSearchFilters(context, _filters);
            if (f == null) return;
            setState(() => _filters = f);
            _run();
          }),
          PopupMenuButton<String>(
            tooltip: 'Order',
            icon: const Icon(Icons.sort),
            initialValue: _order,
            onSelected: (o) {
              setState(() => _order = o);
              _run();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'name', child: Text('Name')),
              PopupMenuItem(value: 'edhrec', child: Text('Popular in Commander')),
              PopupMenuItem(value: 'released', child: Text('Newest')),
              PopupMenuItem(value: 'usd', child: Text('Price')),
              PopupMenuItem(value: 'cmc', child: Text('Mana value')),
            ],
          ),
        ]),
      ),
      Expanded(
        child: p == null
            ? const EmptyState(
                icon: Icons.travel_explore,
                title: 'Search every Magic card',
                body: 'Type a name, or use Scryfall search syntax:\n'
                    't:shark  ·  c:ub  ·  o:"draw a card"  ·  id<=ur f:commander  ·  set:dft',
              )
            : p.error != null && p.cards.isEmpty
                ? EmptyState(icon: Icons.error_outline, title: 'Search failed', body: p.error)
                : p.cards.isEmpty && !p.loading
                    ? const EmptyState(icon: Icons.search_off, title: 'No cards found')
                    : _CardGrid(
                        services: widget.services,
                        cards: _applyOwned(widget.services, p.cards, _filters.owned),
                        loading: p.loading,
                        hasMore: p.hasMore,
                        onMore: () => p.next(() {
                          if (mounted) setState(() {});
                        }),
                        header: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Text(
                            '${p.total} cards${_filters.isEmpty ? '' : ' · filtered'}'
                            '${_filters.owned == OwnedFilter.any ? '' : ' (${_filters.owned == OwnedFilter.owned ? 'owned' : 'not owned'} shown)'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
      ),
    ]);
  }
}

// ───────────────────────── Deck suggestions ─────────────────────────

class _DeckSuggestions extends StatefulWidget {
  final AppServices services;
  const _DeckSuggestions({required this.services});

  @override
  State<_DeckSuggestions> createState() => _DeckSuggestionsState();
}

class _DeckSuggestionsState extends State<_DeckSuggestions> with AutomaticKeepAliveClientMixin {
  String? _deckId;
  bool _synergy = true;
  SearchFilters _filters = const SearchFilters();
  DeckSuggestionQueries? _queries;
  String? _commanderError;
  _ResultPager? _pager;
  bool _loadingCommander = false;

  @override
  bool get wantKeepAlive => true;

  List<Deck> get _decks => widget.services.decks.decks.where((d) => d.commanders.isNotEmpty).toList();

  Future<void> _selectDeck(String id) async {
    setState(() {
      _deckId = id;
      _queries = null;
      _pager = null;
      _commanderError = null;
      _loadingCommander = true;
      _synergy = true;
    });
    final deck = widget.services.decks.byId(id);
    if (deck == null) {
      setState(() {
        _loadingCommander = false;
        _commanderError = 'That deck no longer exists';
      });
      return;
    }
    try {
      // Colour identity and themes come from the commander(s).
      final ci = <String>{};
      var types = '', text = '';
      for (final cmd in deck.commanders) {
        final j = await widget.services.scryfall.namedJson(cmd.name);
        if (j == null) throw UserError('Scryfall doesn\'t know a card called "${cmd.name}"');
        ci.addAll(((j['color_identity'] as List?) ?? const []).cast<String>());
        final faces = j['card_faces'] as List?;
        types += ' ${j['type_line'] ?? (faces?.first as Map?)?['type_line'] ?? ''}';
        text += ' ${j['oracle_text'] ?? faces?.map((f) => (f as Map)['oracle_text'] ?? '').join(' ') ?? ''}';
      }
      const order = ['W', 'U', 'B', 'R', 'G'];
      final q = suggestionQueries(
        colorIdentity: order.where(ci.contains).toList(),
        typeLine: types.trim(),
        oracleText: text,
      );
      if (!mounted || _deckId != id) return;
      setState(() {
        _queries = q;
        _loadingCommander = false;
        if (q.synergy == null) _synergy = false;
      });
      _load();
    } catch (e) {
      if (!mounted || _deckId != id) return;
      setState(() {
        _commanderError = errorText(e);
        _loadingCommander = false;
      });
    }
  }

  void _load() {
    final q = _queries;
    if (q == null) return;
    final base = _synergy && q.synergy != null ? q.synergy! : q.staples;
    // Colours come from the commander, so the colour filter isn't used here.
    final query = combineQuery(base, _filters.toQuery(includeColours: false));
    final p = _ResultPager(widget.services.scryfall, query, order: 'edhrec');
    setState(() => _pager = p);
    p.next(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final decks = _decks;
    if (decks.isEmpty) {
      return const EmptyState(
        icon: Icons.layers_outlined,
        title: 'No decks with a commander yet',
        body: 'Import a Commander deck on the Decks tab (with a "Commander" section or [Commander] tag). '
            'Suggestions here are based on the commander\'s colours, creature types and themes.',
      );
    }
    final deck = _deckId == null ? null : widget.services.decks.byId(_deckId!);
    final inDeck = {for (final c in deck?.cards ?? const <DeckCard>[]) c.key};
    final p = _pager;
    final shown = p == null
        ? const <CardPrint>[]
        : p.cards
            .where((c) => !inDeck.contains(nameKey(c.name)))
            .toList();
    final visible = _applyOwned(widget.services, shown, _filters.owned);
    final q = _queries;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DropdownButtonFormField<String>(
          initialValue: _deckId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Deck', border: OutlineInputBorder(), isDense: true),
          items: [
            for (final d in decks)
              DropdownMenuItem(
                value: d.id,
                child: Text('${d.name} · ${d.commanders.map((c) => c.name).join(' & ')}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) _selectDeck(id);
          },
        ),
      ),
      if (q != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: const Text('Synergy'), enabled: q.synergy != null),
                const ButtonSegment(value: false, label: Text('Staples')),
              ],
              selected: {_synergy},
              onSelectionChanged: (v) {
                setState(() => _synergy = v.first);
                _load();
              },
            ),
            const Spacer(),
            _filterButton(_filters, () async {
              final f = await showSearchFilters(context, _filters, showColours: false);
              if (f == null) return;
              setState(() => _filters = f);
              _load();
            }),
          ]),
        ),
      Expanded(
        child: _deckId == null
            ? const EmptyState(icon: Icons.lightbulb_outline, title: 'Pick a deck to see suggestions')
            : _loadingCommander
                ? const Center(child: CircularProgressIndicator())
                : _commanderError != null
                    ? EmptyState(icon: Icons.error_outline, title: 'Couldn\'t load the commander', body: _commanderError)
                    : p == null
                        ? const SizedBox()
                        : p.error != null && p.cards.isEmpty
                            ? EmptyState(icon: Icons.error_outline, title: 'Search failed', body: p.error)
                            : _CardGrid(
                                services: widget.services,
                                cards: visible,
                                loading: p.loading,
                                hasMore: p.hasMore,
                                forDeckId: _deckId,
                                onMore: () => p.next(() {
                                  if (mounted) setState(() {});
                                }),
                                header: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                  child: Text(
                                    _synergy && q?.synergy != null
                                        ? 'Popular Commander cards in your colours that match: ${q!.themes.join(', ')}. '
                                            'Cards already in the deck are hidden.'
                                        : 'The most-played Commander cards in your colours, not already in the deck.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ),
      ),
    ]);
  }
}
