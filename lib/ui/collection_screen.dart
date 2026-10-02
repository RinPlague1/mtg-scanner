import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/collection.dart';

class CollectionScreen extends StatelessWidget {
  final CollectionStore collection;
  const CollectionScreen({super.key, required this.collection});

  Future<void> _export(BuildContext context) async {
    final file = await collection.exportCsv();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MTG collection export',
      text: 'Moxfield-format CSV (Collection → Import)',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: collection,
      builder: (context, _) {
        final entries = collection.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text('Collection · ${collection.totalCards} cards'),
            actions: [
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.ios_share),
                onPressed: entries.isEmpty ? null : () => _export(context),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(child: Text('Nothing scanned yet'))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Estimated value €${collection.totalEur.toStringAsFixed(2)} (Scryfall prices)'),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final c = e.card;
                        return ListTile(
                          leading: c.imageUrl == null
                              ? const Icon(Icons.style)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image.network(c.imageUrl!, width: 36),
                                ),
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.setCode.toUpperCase()} #${c.collectorNumber}'
                            '${e.foil ? ' · foil' : ''}'
                            '${e.priceEur != null ? ' · €${e.priceEur!.toStringAsFixed(2)}' : ''}',
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () => collection.setQuantity(e, e.quantity - 1),
                            ),
                            Text('${e.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () => collection.setQuantity(e, e.quantity + 1),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                ]),
        );
      },
    );
  }
}
