import 'package:flutter/material.dart';

import '../services.dart';
import '../social/backend.dart';
import 'collection_screen.dart';
import 'decks_screen.dart';
import 'friends_screen.dart';
import 'scanner_screen.dart';
import 'search_screen.dart';
import 'trades_screen.dart';

class HomeShell extends StatefulWidget {
  final AppServices services;
  const HomeShell({super.key, required this.services});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.services.social.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    // Only the visible tab is built, so the camera is released when you leave Scan.
    final body = switch (_tab) {
      0 => ScannerScreen(collection: s.collection, scryfall: s.scryfall, settings: s.settings, buffer: s.buffer),
      1 => CollectionScreen(services: s),
      2 => SearchScreen(services: s),
      3 => DecksScreen(services: s),
      4 => FriendsScreen(services: s),
      _ => TradesScreen(services: s),
    };
    return Scaffold(
      body: body,
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([s.social, s.buffer]),
        builder: (context, _) {
          final scanned = s.buffer.count;
          final me = s.backend.uid;
          final requests = s.social.incomingRequests.length;
          final waiting = me == null
              ? 0
              : s.social.trades
                  .where((t) =>
                      (t.status == TradeStatus.proposed && t.toUser == me) ||
                      (t.status == TradeStatus.accepted && !t.iMarkedDone(me)))
                  .length;
          return NavigationBar(
            selectedIndex: _tab,
            // Six tabs: show the label only on the selected one so they fit.
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: scanned > 0,
                  label: Text('$scanned'),
                  child: const Icon(Icons.document_scanner_outlined),
                ),
                label: 'Scan',
              ),
              const NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), label: 'Collection'),
              const NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              const NavigationDestination(icon: Icon(Icons.layers_outlined), label: 'Decks'),
              NavigationDestination(
                icon: Badge(isLabelVisible: requests > 0, label: Text('$requests'), child: const Icon(Icons.people_outline)),
                label: 'Friends',
              ),
              NavigationDestination(
                icon: Badge(isLabelVisible: waiting > 0, label: Text('$waiting'), child: const Icon(Icons.swap_horiz)),
                label: 'Trades',
              ),
            ],
          );
        },
      ),
    );
  }
}
