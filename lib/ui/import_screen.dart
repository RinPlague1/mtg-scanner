import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/importer.dart';
import '../data/list_parser.dart';
import '../data/models.dart';
import '../services.dart';
import '../social/backend.dart';
import 'widgets.dart';

enum ImportTarget {
  collection('Collection'),
  showcase('Showcase'),
  trade('Up for trade'),
  deck('New deck'),
  wishlist('Wishlist');

  final String label;
  const ImportTarget(this.label);

  Binder? get binder => switch (this) {
        ImportTarget.collection => Binder.collection,
        ImportTarget.showcase => Binder.showcase,
        ImportTarget.trade => Binder.trade,
        _ => null,
      };
}

/// Import a TXT or CSV list (from a file or pasted) into a binder, a new deck
/// or the wishlist.
class ImportScreen extends StatefulWidget {
  final AppServices services;
  final ImportTarget initialTarget;
  const ImportScreen({super.key, required this.services, this.initialTarget = ImportTarget.collection});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late ImportTarget _target = widget.initialTarget;
  final _text = TextEditingController();
  final _deckName = TextEditingController();
  DeckStatus _deckStatus = DeckStatus.built;
  String? _fileName;
  ParsedList? _parsed;
  bool _busy = false;
  String? _progress;

  @override
  void dispose() {
    _text.dispose();
    _deckName.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'Card lists',
      extensions: ['csv', 'txt'],
      mimeTypes: ['text/csv', 'text/plain', 'text/comma-separated-values', 'application/csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text', 'public.plain-text'],
    );
    try {
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      final content = await file.readAsString();
      setState(() {
        _fileName = file.name;
        _text.text = content;
      });
      _parse();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not read the file: $e');
    }
  }

  void _parse() {
    final p = parseCardList(_text.text, fileName: _fileName);
    setState(() => _parsed = p);
    if (_target == ImportTarget.deck && _deckName.text.isEmpty) {
      final commander = p.lines.where((l) => l.commander).firstOrNull;
      final fromFile = _fileName?.replaceAll(RegExp(r'\.(csv|txt)$', caseSensitive: false), '');
      _deckName.text = commander?.name ?? fromFile ?? '';
    }
  }

  Future<void> _save() async {
    final p = _parsed;
    if (p == null || p.lines.isEmpty) return;
    final s = widget.services;
    setState(() => _busy = true);
    try {
      switch (_target) {
        case ImportTarget.deck:
          final name = _deckName.text.trim().isEmpty ? 'Imported deck' : _deckName.text.trim();
          final deck = deckFromLines(name, p.lines, _deckStatus);
          await s.decks.add(deck);
          if (!mounted) return;
          showMessage(context, 'Saved "${deck.name}" · ${deck.cardCount} cards');
          Navigator.pop(context);
        case ImportTarget.wishlist:
          for (final l in p.lines) {
            await s.wishlist.add(l.name, l.qty);
          }
          if (!mounted) return;
          showMessage(context, 'Added ${p.lines.length} cards to your wishlist');
          Navigator.pop(context);
        case ImportTarget.collection || ImportTarget.showcase || ImportTarget.trade:
          s.scryfall.onRateLimited = (secs) {
            if (mounted) setState(() => _progress = 'Scryfall asked us to slow down, waiting $secs s…');
          };
          final r = await resolveForCollection(s.scryfall, p.lines, _target.binder!, onProgress: (done, total) {
            if (mounted) setState(() => _progress = 'Looking up cards… $done of $total');
          });
          s.scryfall.onRateLimited = null;
          await s.collection.addAll(r.entries);
          if (!mounted) return;
          final added = r.entries.fold(0, (n, e) => n + e.quantity);
          if (r.unmatched.isEmpty) {
            showMessage(context, 'Added $added cards to ${_target.label}');
            Navigator.pop(context);
          } else {
            await _showUnmatched(added, r.unmatched);
            if (mounted) Navigator.pop(context);
          }
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      widget.services.scryfall.onRateLimited = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _showUnmatched(int added, List<ImportLine> unmatched) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Added $added cards'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${unmatched.length} lines did not match a card on Scryfall and were skipped:'),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final l in unmatched)
                  Text('${l.qty} ${l.name}${l.setCode != null ? ' (${l.setCode!.toUpperCase()})' : ''}'),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    final online = _target.binder != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Import cards')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Import into', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final t in ImportTarget.values)
            ChoiceChip(
              label: Text(t.label),
              selected: t == _target,
              onSelected: (_) => setState(() {
                _target = t;
                if (_text.text.isNotEmpty) _parse();
              }),
            ),
        ]),
        if (_target == ImportTarget.deck) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _deckName,
            decoration: const InputDecoration(labelText: 'Deck name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<DeckStatus>(
            segments: [
              for (final st in DeckStatus.values) ButtonSegment(value: st, label: Text(st.label)),
            ],
            selected: {_deckStatus},
            onSelectionChanged: (v) => setState(() => _deckStatus = v.first),
          ),
          const SizedBox(height: 4),
          Text(
            switch (_deckStatus) {
              DeckStatus.built => 'Owned cards are kept back from trades; missing cards go on your wants.',
              DeckStatus.brewing => "Missing cards go on your wants; nothing is kept back.",
              DeckStatus.retired => 'Kept for reference; its cards count as spares.',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose TXT or CSV'),
            onPressed: _busy ? null : _pickFile,
          ),
          const SizedBox(width: 12),
          if (_fileName != null) Expanded(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Or paste a list',
            hintText: '1 Sol Ring\n1x Arcane Signet (C21) 263\n4 Island *F*',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => _parse(),
        ),
        const SizedBox(height: 8),
        Text(
          'Works with ManaBox, Moxfield, Deckbox and Archidekt exports, plain "1 Card name" lists, '
          'and any CSV with a Name column.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (p != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${p.cardCount} cards on ${p.lines.length} lines (${p.wasCsv ? 'CSV' : 'text list'})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (p.lines.any((l) => l.commander))
                  Text('Commander: ${p.lines.where((l) => l.commander).map((l) => l.name).join(' & ')}'),
                if (p.problems.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${p.problems.length} lines could not be read:',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  for (final pr in p.problems.take(5)) Text(pr, style: Theme.of(context).textTheme.bodySmall),
                  if (p.problems.length > 5) Text('…and ${p.problems.length - 5} more'),
                ],
                const SizedBox(height: 6),
                for (final l in p.lines.take(8))
                  Text(
                    '${l.qty} ${l.name}'
                    '${l.setCode != null ? ' (${l.setCode!.toUpperCase()}${l.collectorNumber != null ? ' ${l.collectorNumber}' : ''})' : ''}'
                    '${l.foil ? ' · foil' : ''}'
                    '${l.section != 'main' && l.section != 'commander' ? ' · ${l.section}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (p.lines.length > 8) Text('…and ${p.lines.length - 8} more lines'),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_busy && online ? (_progress ?? 'Looking up cards…') : 'Import into ${_target.label}'),
          onPressed: _busy || p == null || p.lines.isEmpty ? null : _save,
        ),
        if (online)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.services.cardDb.db != null
                  ? 'Cards are matched using the offline card data on this phone; only cards newer than it are looked up online.'
                  : 'Cards are looked up on Scryfall (about 150 a second for big lists). For instant imports, download the '
                      'offline card data in the scanner settings (⚙ on the Scan tab).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ]),
    );
  }
}
