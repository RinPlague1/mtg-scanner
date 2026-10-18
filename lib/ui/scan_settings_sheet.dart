import 'package:flutter/material.dart';

import '../data/card_db.dart';
import '../data/scryfall.dart';
import '../data/settings.dart';

Future<void> showScanSettings(BuildContext context, AppSettings settings, ScryfallClient scryfall) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ScanSettingsSheet(settings: settings, scryfall: scryfall),
  );
}

class _ScanSettingsSheet extends StatefulWidget {
  final AppSettings settings;
  final ScryfallClient scryfall;
  const _ScanSettingsSheet({required this.settings, required this.scryfall});

  @override
  State<_ScanSettingsSheet> createState() => _ScanSettingsSheetState();
}

class _ScanSettingsSheetState extends State<_ScanSettingsSheet> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    try {
      final b = await widget.scryfall.cardNamesSize();
      if (mounted) setState(() => _bytes = b);
    } catch (_) {}
  }

  Future<void> _choose(NameMatching m) async {
    await widget.settings.setNameMatching(m);
    if (m == NameMatching.scryfallOnline) {
      // Nothing downloaded is kept in online mode.
      await widget.scryfall.deleteCardNames();
    }
    await _refreshSize();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.settings.nameMatching;
    final theme = Theme.of(context);
    final size = _bytes == null ? null : '${(_bytes! / 1024 / 1024).toStringAsFixed(1)} MB';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: RadioGroup<NameMatching>(
          groupValue: current,
          onChanged: (m) {
            if (m != null) _choose(m);
          },
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Card name matching', style: theme.textTheme.titleMedium),
            ),
            RadioListTile<NameMatching>(
              value: NameMatching.offlineList,
              title: Text(NameMatching.offlineList.label),
              subtitle: Text(
                'Downloads Scryfall\'s card-name list once (about 1 MB, refreshed weekly). '
                'Faster, copes better with blurry text, and names match without a connection.'
                '${size != null ? '\nOn this phone: $size' : ''}',
              ),
            ),
            RadioListTile<NameMatching>(
              value: NameMatching.scryfallOnline,
              title: Text(NameMatching.scryfallOnline.label),
              subtitle: const Text(
                'Nothing is downloaded. Each scan is sent to Scryfall\'s search, so you need a '
                'connection to scan and it may take a moment longer to lock on.',
              ),
            ),
            const Divider(height: 24),
            if (widget.scryfall.local != null) _CardDataSection(store: widget.scryfall.local!),
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('Show what the scanner reads'),
              subtitle: const Text('Shows the raw text from the title and set line, for troubleshooting.'),
              value: widget.settings.showScanDebug,
              onChanged: (v) async {
                await widget.settings.setShowScanDebug(v);
                if (mounted) setState(() {});
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Download / update / remove the offline card data.
class _CardDataSection extends StatelessWidget {
  final CardDbStore store;
  const _CardDataSection({required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final db = store.db;
        final mb = store.fileBytes == null ? null : (store.fileBytes! / 1024 / 1024).toStringAsFixed(0);
        final when = store.downloadedAt;
        final age = when == null ? null : DateTime.now().difference(when).inDays;
        final String info;
        if (store.downloading) {
          info = 'Downloading… ${((store.progress ?? 0) * 100).round()}%. You can keep using the app.';
        } else if (store.loading) {
          info = 'Loading…';
        } else if (db != null) {
          info = '${db.printingCount} printings of ${db.cardCount} cards · $mb MB · '
              '${age == 0 ? 'updated today' : 'updated $age day${age == 1 ? '' : 's'} ago'}'
              '${store.isStale ? '. Prices may be out of date: update when you\'re on Wi-Fi.' : ''}';
        } else {
          info = 'Not downloaded. Every scan, deck and printing list asks Scryfall online.';
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Offline card data', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Every paper printing\'s set, number, type, mana cost and price, stored on the phone '
              '(about 40 MB) so scans, decks and printing lists load instantly. Card pictures '
              'aren\'t stored: small ones load for lists and full-size ones when you open a card. '
              'The download from Scryfall is larger than what\'s kept, so use Wi-Fi.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(info),
            if (store.downloading) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: store.progress),
            ],
            if (store.error != null)
              Text(store.error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download),
                label: Text(db == null ? 'Download' : 'Update'),
                onPressed: store.downloading || store.loading ? null : store.download,
              ),
              if (db != null && !store.downloading)
                TextButton(onPressed: store.delete, child: const Text('Remove')),
            ]),
          ]),
        );
      },
    );
  }
}
