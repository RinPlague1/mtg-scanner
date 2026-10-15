import 'package:flutter/material.dart';

import '../data/collection.dart';
import '../data/collection_query.dart';
import '../data/models.dart';
import 'widgets.dart';

const colourNames = {
  'W': 'White',
  'U': 'Blue',
  'B': 'Black',
  'R': 'Red',
  'G': 'Green',
  'C': 'Colourless',
  'M': 'Multicolour',
};

/// Filter sheet. Returns the new query, or null if dismissed.
Future<CollectionQuery?> showFilterSheet(BuildContext context, CollectionQuery q, List<String> allTags) {
  return showModalBottomSheet<CollectionQuery>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(initial: q, allTags: allTags),
  );
}

class _FilterSheet extends StatefulWidget {
  final CollectionQuery initial;
  final List<String> allTags;
  const _FilterSheet({required this.initial, required this.allTags});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CollectionQuery q = widget.initial;

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  Widget _section(String title, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
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
            _section('Colour identity', [
              for (final c in colourLetters)
                FilterChip(
                  label: Text(colourNames[c]!),
                  selected: q.colours.contains(c),
                  onSelected: (_) => setState(() => q = q.copyWith(colours: _toggle(q.colours, c))),
                ),
            ]),
            _section('Type', [
              for (final t in cardTypes)
                FilterChip(
                  label: Text(t),
                  selected: q.types.contains(t),
                  onSelected: (_) => setState(() => q = q.copyWith(types: _toggle(q.types, t))),
                ),
            ]),
            _section('Rarity', [
              for (final r in rarities)
                FilterChip(
                  label: Text(r[0].toUpperCase() + r.substring(1)),
                  selected: q.rarities.contains(r),
                  onSelected: (_) => setState(() => q = q.copyWith(rarities: _toggle(q.rarities, r))),
                ),
            ]),
            _section('Condition', [
              for (final c in CardCondition.values)
                FilterChip(
                  label: Text(c.code),
                  tooltip: c.label,
                  selected: q.conditions.contains(c),
                  onSelected: (_) => setState(() => q = q.copyWith(conditions: _toggle(q.conditions, c))),
                ),
            ]),
            _section('Finish', [
              for (final f in FoilFilter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    FoilFilter.any => 'Any',
                    FoilFilter.foil => 'Foil only',
                    FoilFilter.nonFoil => 'Non-foil only',
                  }),
                  selected: q.foil == f,
                  onSelected: (_) => setState(() => q = q.copyWith(foil: f)),
                ),
            ]),
            if (widget.allTags.isNotEmpty)
              _section('Tags', [
                for (final t in widget.allTags)
                  FilterChip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(t),
                    selected: q.tags.contains(t),
                    onSelected: (_) => setState(() => q = q.copyWith(tags: _toggle(q.tags, t))),
                  ),
              ]),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              TextButton(
                onPressed: q.filterCount == 0 ? null : () => setState(() => q = q.cleared()),
                child: const Text('Clear all'),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, q), child: const Text('Show cards')),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Tag editor for one or more entries. Tags on every entry start ticked;
/// unticking removes them, ticking or typing a new one adds it.
Future<void> showTagDialog(BuildContext context, CollectionStore store, List<CollectionEntry> entries) async {
  final result = await showDialog<({Set<String> add, Set<String> remove})>(
    context: context,
    builder: (_) => _TagDialog(store: store, entries: entries),
  );
  if (result != null) await store.tagAll(entries, add: result.add, remove: result.remove);
}

class _TagDialog extends StatefulWidget {
  final CollectionStore store;
  final List<CollectionEntry> entries;
  const _TagDialog({required this.store, required this.entries});

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final List<String> _tags = widget.store.allTags;
  late final Set<String> _onAll = {
    for (final t in _tags)
      if (widget.entries.every((e) => e.tags.contains(t))) t,
  };
  late final Set<String> _onSome = {
    for (final t in _tags)
      if (widget.entries.any((e) => e.tags.contains(t))) t,
  };
  late final Set<String> _checked = {..._onAll};
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _addNew() {
    final t = _new.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (!_tags.contains(t)) _tags.add(t);
      _checked.add(t);
      _new.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.entries.length;
    return AlertDialog(
      title: Text(n == 1 ? 'Tags' : 'Tags for $n cards'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _new,
                autofocus: _tags.isEmpty,
                decoration: const InputDecoration(hintText: 'New tag, e.g. To sell'),
                onSubmitted: (_) => _addNew(),
              ),
            ),
            IconButton(icon: const Icon(Icons.add), onPressed: _addNew),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in _tags)
                CheckboxListTile(
                  dense: true,
                  title: Text(t),
                  // Dash = on some of the selected cards; leaving it alone keeps it as is.
                  tristate: _onSome.contains(t) && !_onAll.contains(t),
                  value: _checked.contains(t)
                      ? true
                      : (_onSome.contains(t) && !_onAll.contains(t) && !_touched.contains(t) ? null : false),
                  onChanged: (_) => setState(() {
                    _touched.add(t);
                    if (_checked.contains(t)) {
                      _checked.remove(t);
                    } else {
                      _checked.add(t);
                    }
                  }),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            _addNew();
            final add = {..._checked};
            // Only remove tags the user actually unticked.
            final remove = {for (final t in _touched) if (!_checked.contains(t)) t};
            Navigator.pop(context, (add: add, remove: remove));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  final Set<String> _touched = {};
}

/// Rename or delete tags across the whole collection.
class ManageTagsScreen extends StatelessWidget {
  final CollectionStore store;

  /// Called with a tag to show only those cards.
  final ValueChanged<String> onShow;
  const ManageTagsScreen({super.key, required this.store, required this.onShow});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tags = store.allTags;
        return Scaffold(
          appBar: AppBar(title: const Text('Tags')),
          body: tags.isEmpty
              ? const EmptyState(
                  icon: Icons.label_outline,
                  title: 'No tags yet',
                  body: 'Long-press cards in your collection to select them, then tap the tag button. '
                      'Tags are your own labels, like "Aang staples" or "To sell".',
                )
              : ListView(children: [
                  for (final t in tags)
                    ListTile(
                      leading: const Icon(Icons.label_outline),
                      title: Text(t),
                      subtitle: Text('${store.countTagged(t)} cards'),
                      onTap: () {
                        onShow(t);
                        Navigator.pop(context);
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'rename') {
                            final c = TextEditingController(text: t);
                            final name = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Rename tag'),
                                content: TextField(controller: c, autofocus: true),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Rename')),
                                ],
                              ),
                            );
                            if (name != null) await store.renameTag(t, name);
                          } else if (v == 'delete') {
                            await store.deleteTag(t);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete tag (cards stay)')),
                        ],
                      ),
                    ),
                ]),
        );
      },
    );
  }
}
