import 'package:flutter/material.dart';

import '../data/card_db.dart' show imageAtSize;
import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../social/backend.dart';

class CardThumb extends StatelessWidget {
  final String? url;
  final double width;
  const CardThumb(this.url, {super.key, this.width = 36});

  @override
  Widget build(BuildContext context) {
    final raw = url;
    if (raw == null) return SizedBox(width: width, child: const Icon(Icons.style));
    // Small list thumbnails load Scryfall's small image (much less data).
    final u = width <= 60 ? imageAtSize(raw, 'small') : raw;
    return ClipRRect(
      borderRadius: BorderRadius.circular(width / 12),
      child: Image.network(
        u,
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SizedBox(width: width, child: const Icon(Icons.style)),
      ),
    );
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [action], showing its error (if any) as a snack bar.
Future<bool> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
    return false;
  }
}

class TradeCardTile extends StatelessWidget {
  final TradeCard card;
  final Widget? trailing;
  final String? note;
  final VoidCallback? onTap;
  const TradeCardTile(this.card, {super.key, this.trailing, this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bits = [
      if (card.setCode != null && card.setCode!.isNotEmpty) card.setCode!.toUpperCase(),
      if (card.foil) 'foil',
      if (card.listed) 'listed',
      if (card.priceEur != null) gbp(card.priceEur),
      ?note,
    ];
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CardThumb(card.imageUrl, width: 32),
      title: Text('${card.qty}× ${card.name}'),
      subtitle: bits.isEmpty ? null : Text(bits.join(' · ')),
      trailing: trailing,
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Colour for a mana symbol letter (W U B R G), grey for generic/colourless.
Color manaColour(String symbol) => switch (symbol) {
      'W' => const Color(0xFFF3EDC8),
      'U' => const Color(0xFF3D8FD1),
      'B' => const Color(0xFF6E6268),
      'R' => const Color(0xFFE0533D),
      'G' => const Color(0xFF2E9A5B),
      _ => const Color(0xFFBEB9B2),
    };

/// A mana cost like "{2}{U}{U}" drawn as small coloured pips.
class ManaCost extends StatelessWidget {
  final String cost;
  final double size;
  const ManaCost(this.cost, {super.key, this.size = 15});

  @override
  Widget build(BuildContext context) {
    if (cost.isEmpty) return const SizedBox.shrink();
    final faces = cost.split(' // ');
    final children = <Widget>[];
    for (var f = 0; f < faces.length; f++) {
      if (f > 0) children.add(Text(' // ', style: TextStyle(fontSize: size * 0.8)));
      for (final m in RegExp(r'\{([^}]+)\}').allMatches(faces[f])) {
        final sym = m.group(1)!;
        final parts = sym.split('/');
        final colour = parts.firstWhere((p) => 'WUBRG'.contains(p) && p.length == 1, orElse: () => '');
        final label = parts.length > 1 ? parts.where((p) => p != 'P').join() : sym;
        children.add(Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(left: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: manaColour(colour), shape: BoxShape.circle),
          child: Text(
            label,
            style: TextStyle(
              fontSize: size * (label.length > 1 ? 0.45 : 0.65),
              fontWeight: FontWeight.w700,
              color: colour == 'U' || colour == 'B' ? Colors.white : Colors.black,
              height: 1,
            ),
          ),
        ));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
