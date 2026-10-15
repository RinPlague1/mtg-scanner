import 'package:flutter/material.dart';

import '../data/scryfall.dart';
import '../data/settings.dart';

Future<void> showScanSettings(BuildContext context, AppSettings settings, ScryfallClient scryfall) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
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
      child: Padding(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Either way, looking up the exact printing and price uses Scryfall online.',
                style: theme.textTheme.bodySmall,
              ),
            ),
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
