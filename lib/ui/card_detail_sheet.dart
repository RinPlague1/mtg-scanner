import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/card_db.dart' show imageAtSize;
import '../data/decks.dart';
import '../data/models.dart';
import '../data/prices.dart';
import '../data/scryfall.dart';
import '../services.dart';
import 'widgets.dart';

/// Card details from Scryfall with actions: add to collection, wishlist or a
/// deck, or open the card on scryfall.com.
Future<void> showCardDetail(BuildContext context, AppServices services, CardPrint card, {String? forDeckId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardDetail(services: services, card: card, forDeckId: forDeckId),
  );
}

class _CardDetail extends StatefulWidget {
  final AppServices services;
  final CardPrint card;
  final String? forDeckId;
  const _CardDetail({required this.services, required this.card, this.forDeckId});

  @override
  State<_CardDetail> createState() => _CardDetailState();
}

class _CardDetailState extends State<_CardDetail> {
  late final Future<Map<String, dynamic>?> _full = widget.services.scryfall.cardJson(widget.card.id);
  bool _foil = false;
  Binder _binder = Binder.collection;
  int _deckQty = 1;

  CardPrint get c => widget.card;

  String _oracle(Map<String, dynamic> j) {
    final faces = j['card_faces'] as List?;
    if (faces != null && faces.isNotEmpty && j['oracle_text'] == null) {
      return faces
          .map((f) => '${(f as Map)['name']}  ${f['mana_cost'] ?? ''}\n${f['type_line'] ?? ''}\n${f['oracle_text'] ?? ''}')
          .join('\n\n');
    }
    return j['oracle_text'] as String? ?? '';
  }

  Future<void> _addToCollection() async {
    await widget.services.collection.add(c, foil: _foil, binder: _binder);
    if (mounted) showMessage(context, 'Added ${c.name} to ${_binder.label}');
  }

  Future<void> _addToWishlist() async {
    await widget.services.wishlist.add(c.name);
    if (mounted) showMessage(context, 'Added ${c.name} to your wishlist');
  }

  Future<void> _addToDeck() async {
    final decks = widget.services.decks.decks;
    if (decks.isEmpty) {
      showMessage(context, 'Import a deck first (Decks tab)');
      return;
    }
    Deck? deck = widget.forDeckId == null ? null : widget.services.decks.byId(widget.forDeckId!);
    deck ??= await showDialog<Deck>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to which deck?'),
        children: [
          for (final d in decks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text('${d.name}  (${d.status.label})'),
            ),
        ],
      ),
    );
    if (deck == null) return;
    final key = nameKey(c.name);
    final existing = deck.byKey(key);
    final basic = c.typeLine.toLowerCase().contains('basic');
    if (existing != null && deck.format == 'commander' && !basic) {
      if (mounted) showMessage(context, '${c.name} is already in ${deck.name}');
      return;
    }
    final n = deck.addCard(c, qty: _deckQty);
    await widget.services.decks.changed();
    final owned = widget.services.collection.ownedCount(key) >= n;
    if (mounted) {
      showMessage(context,
          '${c.name}: $n in ${deck.name}${owned ? '' : '. Missing copies are on your wants'}');
    }
  }

  Future<void> _openScryfall(String? uri) async {
    final url = Uri.parse(uri ?? 'https://scryfall.com/search?q=${Uri.encodeQueryComponent('!"${c.name}"')}');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Could not open the browser');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owned = widget.services.collection.ownedCount(nameKey(c.name));
    final eur = double.tryParse((_foil ? c.priceEurFoil : c.priceEur) ?? '');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<Map<String, dynamic>?>(
        future: _full,
        builder: (context, snap) {
          final j = snap.data;
          final legal = (j?['legalities'] as Map?)?['commander'] as String?;
          return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            if (c.imageUrl != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(imageAtSize(c.imageUrl!, 'large'), height: 340, fit: BoxFit.contain),
                ),
              ),
            const SizedBox(height: 12),
            Text(c.name, style: theme.textTheme.titleLarge),
            Text(
              [
                if (c.typeLine.isNotEmpty) c.typeLine,
                '${c.setName} (${c.setCode.toUpperCase()})',
                if (eur != null) gbp(eur),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (owned > 0) Chip(avatar: const Icon(Icons.check, size: 16), label: Text('You own $owned')),
              if (legal != null)
                Chip(
                  label: Text(legal == 'legal' ? 'Commander legal' : 'Commander: ${legal.replaceAll('_', ' ')}'),
                ),
            ]),
            const SizedBox(height: 8),
            if (j == null && !snap.hasError) const LinearProgressIndicator(),
            if (j != null && _oracle(j).isNotEmpty) ...[
              Text(_oracle(j), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            const Divider(),
            Text('Add to your collection', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final b in Binder.values)
                ChoiceChip(label: Text(b.label), selected: _binder == b, onSelected: (_) => setState(() => _binder = b)),
              FilterChip(label: const Text('Foil'), selected: _foil, onSelected: (v) => setState(() => _foil = v)),
            ]),
            const SizedBox(height: 6),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text('Add to ${_binder.label}'),
              onPressed: _addToCollection,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.favorite_border),
                label: const Text('Wishlist'),
                onPressed: _addToWishlist,
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove),
                  onPressed: _deckQty > 1 ? () => setState(() => _deckQty--) : null,
                ),
                Text('$_deckQty'),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _deckQty++),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.layers_outlined),
                  label: Text(widget.forDeckId != null ? 'Add to this deck' : 'Add to a deck'),
                  onPressed: _addToDeck,
                ),
              ]),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('View on Scryfall'),
                onPressed: () => _openScryfall(j?['scryfall_uri'] as String?),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}
