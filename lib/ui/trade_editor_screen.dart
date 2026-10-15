import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../services.dart';
import 'widgets.dart';

String _id(TradeCard c) => '${c.key}|${c.scryfallId}|${c.foil}';

/// Build or adjust a trade proposal with one friend.
class TradeEditorScreen extends StatefulWidget {
  final AppServices services;
  final String friendId;
  final List<TradeCard> initialGive;
  final List<TradeCard> initialGet;

  /// Set when countering a proposal.
  final String? parentId;

  const TradeEditorScreen({
    super.key,
    required this.services,
    required this.friendId,
    this.initialGive = const [],
    this.initialGet = const [],
    this.parentId,
  });

  @override
  State<TradeEditorScreen> createState() => _TradeEditorScreenState();
}

class _TradeEditorScreenState extends State<TradeEditorScreen> {
  late final List<TradeCard> _myCandidates;
  late final List<TradeCard> _theirCandidates;
  final Map<String, int> _give = {};
  final Map<String, int> _get = {};
  final Set<String> _theyWant = {};
  final Set<String> _iWant = {};
  bool _allMine = false;
  bool _allTheirs = false;
  bool _sending = false;
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    final social = widget.services.social;
    final lists = social.lists[widget.friendId];
    _theyWant.addAll((lists?.wants ?? const []).map((w) => w.key));
    _iWant.addAll(social.myWants.map((w) => w.key));

    List<TradeCard> merge(List<TradeCard> base, List<TradeCard> initial) {
      final out = [...base];
      for (final c in initial) {
        final i = out.indexWhere((x) => _id(x) == _id(c));
        if (i < 0) {
          out.insert(0, c);
        } else if (out[i].qty < c.qty) {
          out[i] = out[i].withQty(c.qty);
        }
      }
      return out;
    }

    _myCandidates = merge(social.mySpares, widget.initialGive);
    _theirCandidates = merge(lists?.spares ?? const [], widget.initialGet);
    for (final c in widget.initialGive) {
      _give[_id(c)] = c.qty;
    }
    for (final c in widget.initialGet) {
      _get[_id(c)] = c.qty;
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  List<TradeCard> _selected(List<TradeCard> from, Map<String, int> sel) => [
        for (final c in from)
          if ((sel[_id(c)] ?? 0) > 0) c.withQty(sel[_id(c)]!),
      ];

  Future<void> _send() async {
    final give = _selected(_myCandidates, _give);
    final get = _selected(_theirCandidates, _get);
    if (give.isEmpty && get.isEmpty) return;
    setState(() => _sending = true);
    final ok = await runGuarded(
      context,
      () => widget.services.social.propose(
        to: widget.friendId,
        give: give,
        receive: get,
        message: _message.text,
        parentId: widget.parentId,
      ),
      success: widget.parentId == null ? 'Trade proposed' : 'Counter-offer sent',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.services.social.nameOf(widget.friendId);
    final give = _selected(_myCandidates, _give);
    final get = _selected(_theirCandidates, _get);
    final giveEur = give.fold(0.0, (s, c) => s + c.totalEur);
    final getEur = get.fold(0.0, (s, c) => s + c.totalEur);

    final mine = _allMine
        ? _myCandidates
        : _myCandidates.where((c) => _theyWant.contains(c.key) || _give.containsKey(_id(c))).toList();
    final theirs = _allTheirs
        ? _theirCandidates
        : _theirCandidates.where((c) => _iWant.contains(c.key) || _get.containsKey(_id(c))).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.parentId == null ? 'Trade with $name' : 'Counter-offer to $name')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text(
                'You give ${gbp(giveEur)} · you get ${gbp(getEur)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send'),
              onPressed: _sending || (give.isEmpty && get.isEmpty) ? null : _send,
            ),
          ]),
        ),
      ),
      body: ListView(children: [
        _section(
          context,
          title: 'You get from $name',
          hint: _allTheirs ? 'All their spares' : 'Their spares you want',
          showAll: _allTheirs,
          onShowAll: (v) => setState(() => _allTheirs = v),
          cards: theirs,
          sel: _get,
          wanted: _iWant,
          wantedLabel: 'you want this',
          empty: 'They have nothing spare that you want. Tap "Show all" to browse everything they offer.',
        ),
        const Divider(),
        _section(
          context,
          title: 'You give',
          hint: _allMine ? 'All your spares' : 'Your spares they want',
          showAll: _allMine,
          onShowAll: (v) => setState(() => _allMine = v),
          cards: mine,
          sel: _give,
          wanted: _theyWant,
          wantedLabel: 'they want this',
          empty: 'Nothing of yours is on their wants. Tap "Show all" to offer something else.',
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _message,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Message (optional)', border: OutlineInputBorder()),
          ),
        ),
      ]),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String hint,
    required bool showAll,
    required ValueChanged<bool> onShowAll,
    required List<TradeCard> cards,
    required Map<String, int> sel,
    required Set<String> wanted,
    required String wantedLabel,
    required String empty,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          FilterChip(label: const Text('Show all'), selected: showAll, onSelected: onShowAll),
        ]),
      ),
      if (cards.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(empty)),
      for (final c in cards)
        Builder(builder: (context) {
          final id = _id(c);
          final n = sel[id] ?? 0;
          return TradeCardTile(
            c,
            note: wanted.contains(c.key) ? wantedLabel : null,
            onTap: () => setState(() {
              if (n > 0) {
                sel.remove(id);
              } else {
                sel[id] = c.qty;
              }
            }),
            trailing: n == 0
                ? const Icon(Icons.add_circle_outline)
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => setState(() {
                        if (n <= 1) {
                          sel.remove(id);
                        } else {
                          sel[id] = n - 1;
                        }
                      }),
                    ),
                    Text('$n'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: n < c.qty ? () => setState(() => sel[id] = n + 1) : null,
                    ),
                  ]),
          );
        }),
    ]);
  }
}
