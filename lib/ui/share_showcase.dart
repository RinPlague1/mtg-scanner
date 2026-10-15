import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../services.dart';
import 'widgets.dart';

/// Shares your Showcase. With an account and a hosted viewer page
/// (SHOWCASE_URL) it's a link anyone can open; otherwise a text list.
Future<void> shareShowcase(BuildContext context, AppServices s) async {
  final token = s.backend.profile?.shareToken;
  if (s.backend.signedIn && token != null && AppConfig.showcaseUrl.isNotEmpty) {
    await s.sync.pushNow(); // make sure the link shows what's on the phone
    final params = Uri(queryParameters: {
      'u': AppConfig.supabaseUrl,
      'k': AppConfig.supabaseAnonKey,
      't': token,
    }).query;
    final link = '${AppConfig.showcaseUrl}#$params';
    await SharePlus.instance.share(ShareParams(
      text: link,
      subject: '${s.backend.profile!.label}\'s MTG Showcase',
    ));
    return;
  }

  final cards = s.collection.inBinder(Binder.showcase);
  if (cards.isEmpty) {
    if (context.mounted) showMessage(context, 'Your Showcase is empty');
    return;
  }
  final text = StringBuffer('My MTG Showcase\n\n');
  for (final e in cards) {
    text.writeln('${e.quantity}× ${e.card.name} (${e.card.setCode.toUpperCase()})${e.foil ? ' ✦ foil' : ''}');
  }
  await SharePlus.instance.share(ShareParams(text: text.toString(), subject: 'My MTG Showcase'));
}
