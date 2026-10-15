import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../services.dart';
import '../social/backend.dart';
import 'sign_in_panel.dart';
import 'trade_editor_screen.dart';
import 'widgets.dart';

class TradesScreen extends StatefulWidget {
  final AppServices services;
  const TradesScreen({super.key, required this.services});

  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred: refresh() notifies listeners, which must not happen mid-build.
    Future.microtask(widget.services.social.refresh);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.backend, s.social, s.collection, s.decks, s.wishlist, Fx.instance]),
      builder: (context, _) {
        if (!s.backend.signedIn) {
          return Scaffold(appBar: AppBar(title: const Text('Trades')), body: SignInPanel(services: s));
        }
        final me = s.backend.uid!;
        final suggestions = s.social.suggestions;
        final active = s.social.trades.where((t) => t.open).toList();
        final history = s.social.trades.where((t) => !t.open).toList();
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Trades'),
              bottom: TabBar(tabs: [
                Tab(text: 'Suggested (${suggestions.length})'),
                Tab(text: 'Active (${active.length})'),
                const Tab(text: 'History'),
              ]),
            ),
            body: TabBarView(children: [
              RefreshIndicator(
                onRefresh: s.social.refresh,
                child: suggestions.isEmpty
                    ? ListView(children: [
                        EmptyState(
                          icon: Icons.lightbulb_outline,
                          title: s.social.accepted.isEmpty ? 'Add friends to get suggestions' : 'No matches right now',
                          body: 'Suggestions match what friends have spare against your deck gaps and wishlist, '
                              'and your spares against their wants. Import decks to get better matches.',
                        ),
                      ])
                    : ListView(padding: const EdgeInsets.all(8), children: [
                        for (final sg in suggestions) _suggestionCard(context, sg),
                      ]),
              ),
              RefreshIndicator(
                onRefresh: s.social.refresh,
                child: active.isEmpty
                    ? ListView(children: const [
                        EmptyState(icon: Icons.swap_horiz, title: 'No active trades'),
                      ])
                    : ListView(children: [for (final t in active) _tradeTile(context, t, me)]),
              ),
              RefreshIndicator(
                onRefresh: s.social.refresh,
                child: history.isEmpty
                    ? ListView(children: const [EmptyState(icon: Icons.history, title: 'No past trades')])
                    : ListView(children: [for (final t in history) _tradeTile(context, t, me)]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _suggestionCard(BuildContext context, TradeSuggestion sg) {
    final theme = Theme.of(context);
    String names(List<TradeCard> cards) {
      final shown = cards.take(3).map((c) => c.qty > 1 ? '${c.qty}× ${c.name}' : c.name).join(', ');
      return cards.length > 3 ? '$shown +${cards.length - 3} more' : shown;
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TradeEditorScreen(
            services: widget.services,
            friendId: sg.friendId,
            initialGive: sg.youGive,
            initialGet: sg.theyGive,
          ),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(sg.friendName, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (sg.isSwap) const Chip(label: Text('Two-way'), visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 6),
            if (sg.theyGive.isNotEmpty)
              Text('You get ${gbp(sg.theyGiveEur)}: ${names(sg.theyGive)}'),
            if (sg.youGive.isNotEmpty)
              Text('You give ${gbp(sg.youGiveEur)}: ${names(sg.youGive)}', style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _tradeTile(BuildContext context, Trade t, String me) {
    final other = widget.services.social.nameOf(t.otherUser(me));
    final give = t.iGive(me).fold(0, (n, c) => n + c.qty);
    final get = t.iGet(me).fold(0, (n, c) => n + c.qty);
    final (label, color) = statusLabel(t, me, context);
    return ListTile(
      leading: Icon(t.isFrom(me) ? Icons.call_made : Icons.call_received),
      title: Text(t.isFrom(me) ? 'To $other' : 'From $other'),
      subtitle: Text('You give $give · you get $get'),
      trailing: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TradeDetailScreen(services: widget.services, tradeId: t.id),
      )),
    );
  }
}

(String, Color?) statusLabel(Trade t, String me, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return switch (t.status) {
    TradeStatus.proposed => t.isFrom(me) ? ('Waiting', null) : ('Respond', cs.primary),
    TradeStatus.accepted => t.iMarkedDone(me) ? ('Waiting for them', null) : ('Swap & confirm', cs.primary),
    TradeStatus.completed => ('Completed', Colors.greenAccent),
    TradeStatus.declined => ('Declined', cs.error),
    TradeStatus.cancelled => ('Cancelled', cs.outline),
    TradeStatus.countered => ('Countered', cs.outline),
  };
}

class TradeDetailScreen extends StatelessWidget {
  final AppServices services;
  final String tradeId;
  const TradeDetailScreen({super.key, required this.services, required this.tradeId});

  @override
  Widget build(BuildContext context) {
    final s = services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.social, Fx.instance]),
      builder: (context, _) {
        final t = s.social.trades.where((x) => x.id == tradeId).firstOrNull;
        final me = s.backend.uid;
        if (t == null || me == null) return const Scaffold(body: Center(child: Text('Trade not found')));
        final other = s.social.nameOf(t.otherUser(me));
        final give = t.iGive(me), get = t.iGet(me);
        final (label, color) = statusLabel(t, me, context);

        Future<void> act(String action, String done) async {
          await runGuarded(context, () => s.social.respondTrade(t, action), success: done);
        }

        final actions = <Widget>[
          if (t.status == TradeStatus.proposed && !t.isFrom(me)) ...[
            FilledButton(onPressed: () => act('accept', 'Accepted. Meet up and swap!'), child: const Text('Accept')),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TradeEditorScreen(
                  services: s,
                  friendId: t.otherUser(me),
                  initialGive: give,
                  initialGet: get,
                  parentId: t.id,
                ),
              )),
              child: const Text('Counter'),
            ),
            TextButton(onPressed: () => act('decline', 'Declined'), child: const Text('Decline')),
          ],
          if (t.status == TradeStatus.proposed && t.isFrom(me))
            TextButton(onPressed: () => act('cancel', 'Cancelled'), child: const Text('Cancel proposal')),
          if (t.status == TradeStatus.accepted) ...[
            if (!t.iMarkedDone(me))
              FilledButton.icon(
                icon: const Icon(Icons.handshake),
                onPressed: () => act('complete', 'Marked as swapped'),
                label: const Text("We've swapped"),
              ),
            TextButton(onPressed: () => act('cancel', 'Trade cancelled'), child: const Text('Call it off')),
          ],
        ];

        return Scaffold(
          appBar: AppBar(title: Text('Trade with $other')),
          body: RefreshIndicator(
            onRefresh: s.social.refresh,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ListTile(
                title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                subtitle: Text(switch (t.status) {
                  TradeStatus.proposed =>
                    t.isFrom(me) ? 'Waiting for $other to respond.' : '$other proposed this trade.',
                  TradeStatus.accepted => t.iMarkedDone(me)
                      ? 'You marked it as swapped. When $other does too, both collections update.'
                      : 'Accepted. After you swap the cards, tap "We\'ve swapped". '
                          'Your collection updates when you both confirm.',
                  TradeStatus.completed => 'Done. Your collection has been updated.',
                  TradeStatus.declined => 'Declined.',
                  TradeStatus.cancelled => 'Cancelled.',
                  TradeStatus.countered => 'Replaced by a counter-offer.',
                }),
              ),
              if (t.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(padding: const EdgeInsets.all(12), child: Text('"${t.message}"')),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
              _side(context, 'You get · ${gbp(get.fold<double>(0.0, (n, c) => n + c.totalEur))}', get),
              _side(context, 'You give · ${gbp(give.fold<double>(0.0, (n, c) => n + c.totalEur))}', give),
            ]),
          ),
        );
      },
    );
  }

  Widget _side(BuildContext context, String title, List<TradeCard> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (cards.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nothing')),
          for (final c in cards) TradeCardTile(c),
        ],
      );
}
