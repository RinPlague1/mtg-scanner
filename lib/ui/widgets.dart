import 'package:flutter/material.dart';

import '../data/prices.dart';
import '../data/trade_logic.dart';
import '../social/backend.dart';

class CardThumb extends StatelessWidget {
  final String? url;
  final double width;
  const CardThumb(this.url, {super.key, this.width = 36});

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return SizedBox(width: width, child: const Icon(Icons.style));
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
