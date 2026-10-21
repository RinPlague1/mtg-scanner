import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../data/scryfall.dart';
import 'net_image.dart';

/// Bottom sheet listing every printing of [current]'s card. Returns the one
/// tapped, or null if dismissed. Used by the scanner and the collection.
Future<CardPrint?> pickPrinting(BuildContext context, ScryfallClient scryfall, CardPrint current) {
  return showModalBottomSheet<CardPrint>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scroll) => FutureBuilder<List<CardPrint>>(
        future: scryfall.printings(current.name),
        builder: (ctx, snap) {
          if (snap.hasError) return Center(child: Text('Could not load printings: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return ListView.builder(
            controller: scroll,
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final p = list[i];
              final foilOnly = !p.finishes.contains('nonfoil') && p.finishes.contains('foil');
              return ListTile(
                selected: p.id == current.id,
                leading: p.imageUrl == null ? null : NetImage(p.imageUrl!, width: 36),
                title: Text('${p.setName} (${p.setCode.toUpperCase()})'),
                subtitle: Text('#${p.collectorNumber} · ${p.rarity}${foilOnly ? ' · foil only' : ''}'),
                trailing: Text(p.priceEur != null
                    ? gbp(double.tryParse(p.priceEur!))
                    : (p.priceUsd != null ? '\$${p.priceUsd}' : '')),
                onTap: () => Navigator.of(ctx).pop(p),
              );
            },
          );
        },
      ),
    ),
  );
}

/// Whether a printing can be had in foil / non-foil.
bool canBeFoil(CardPrint c) => c.finishes.contains('foil') || c.finishes.contains('etched');
bool canBeNonFoil(CardPrint c) => c.finishes.contains('nonfoil') || c.finishes.isEmpty;

/// Finish to assume when nothing was chosen: non-foil unless the printing
/// only exists in foil.
bool defaultFoil(CardPrint c) => !canBeNonFoil(c) && canBeFoil(c);
