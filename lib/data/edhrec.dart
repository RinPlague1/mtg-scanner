/// Card recommendations for a commander from EDHREC (edhrec.com), which
/// counts what thousands of real decks with that commander play. Parsing is
/// pure Dart and unit-tested (test/edhrec_test.dart).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class EdhrecCard {
  final String name;

  /// How much more often this card is played with this commander than with
  /// others in its colours (-1…1; 0.3 = +30%).
  final double synergy;

  /// Share of this commander's decks that play it (0…1).
  final double inclusion;
  final int decks;

  const EdhrecCard(this.name, this.synergy, this.inclusion, this.decks);

  String get caption {
    final parts = <String>[
      if (inclusion > 0) '${(inclusion * 100).round()}% of decks',
      if (synergy.abs() >= 0.01) '${synergy > 0 ? '+' : ''}${(synergy * 100).round()}% synergy',
    ];
    return parts.join(' · ');
  }
}

class EdhrecSection {
  final String title;
  final String tag;
  final List<EdhrecCard> cards;
  const EdhrecSection(this.title, this.tag, this.cards);
}

class EdhrecPage {
  final String commander;
  final int deckCount;
  final List<EdhrecSection> sections;
  const EdhrecPage(this.commander, this.deckCount, this.sections);
}

/// EDHREC's page name for a card: "Atraxa, Praetors' Voice" →
/// "atraxa-praetors-voice". Double-faced cards use the front face.
String edhrecSlug(String name) {
  var n = nameKey(name);
  n = n.replaceAll(RegExp(r'''['".,!?:]'''), '');
  n = n.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return n.replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Page slug for one commander or a partner pair (EDHREC sorts the pair).
String edhrecCommanderSlug(List<String> commanders) {
  final slugs = commanders.map(edhrecSlug).toList()..sort();
  return slugs.join('-');
}

/// Reads EDHREC's commander page JSON. Sections in EDHREC's order; empty
/// ones dropped. Section titles are tidied ("High Synergy Cards" → "High synergy").
EdhrecPage parseEdhrecPage(Map<String, dynamic> j) {
  final container = (j['container'] as Map?) ?? const {};
  final dict = (container['json_dict'] as Map?) ?? const {};
  final lists = (dict['cardlists'] as List?) ?? const [];
  final sections = <EdhrecSection>[];
  for (final l in lists) {
    final m = l as Map;
    final views = (m['cardviews'] as List?) ?? const [];
    final cards = <EdhrecCard>[];
    for (final v in views) {
      final c = v as Map;
      final name = c['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final num = (c['num_decks'] as num?)?.toInt() ?? (c['inclusion'] as num?)?.toInt() ?? 0;
      final potential = (c['potential_decks'] as num?)?.toInt() ?? 0;
      cards.add(EdhrecCard(
        name,
        (c['synergy'] as num?)?.toDouble() ?? 0,
        potential > 0 ? num / potential : 0,
        num,
      ));
    }
    if (cards.isEmpty) continue;
    var title = (m['header'] as String? ?? m['tag'] as String? ?? 'Cards').trim();
    title = title.replaceAll(RegExp(r'\s+Cards$'), '');
    if (title.isNotEmpty) title = title[0].toUpperCase() + title.substring(1).toLowerCase();
    sections.add(EdhrecSection(title, m['tag'] as String? ?? title, cards));
  }
  final header = (j['header'] as String?) ?? (container['title'] as String?) ?? '';
  final deckCount = (j['num_decks_avg'] as num?)?.toInt() ?? (j['num_decks'] as num?)?.toInt() ?? 0;
  return EdhrecPage(header, deckCount, sections);
}

class EdhrecClient {
  final http.Client _http;
  final _cache = <String, EdhrecPage?>{};
  EdhrecClient([http.Client? client]) : _http = client ?? http.Client();

  Future<Map<String, dynamic>?> _get(String path) async {
    final res = await _http.get(Uri.parse('https://json.edhrec.com/pages$path.json'), headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android) MTGBinder/0.2',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 12));
    if (res.statusCode == 404 || res.statusCode == 403) return null;
    if (res.statusCode != 200) throw Exception('EDHREC ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Recommendations for these commanders, or null if EDHREC has no page.
  /// Partner pairs fall back to the first commander's page.
  Future<EdhrecPage?> commander(List<String> commanders) async {
    final key = edhrecCommanderSlug(commanders);
    if (_cache.containsKey(key)) return _cache[key];
    final tries = [key, if (commanders.length > 1) edhrecSlug(commanders.first)];
    EdhrecPage? page;
    for (final slug in tries) {
      var j = await _get('/commanders/$slug');
      // Some names redirect to EDHREC's canonical page.
      final redirect = j?['redirect'] as String?;
      if (redirect != null && redirect.startsWith('/')) j = await _get(redirect);
      if (j != null) {
        page = parseEdhrecPage(j);
        if (page.sections.isNotEmpty) break;
      }
    }
    _cache[key] = page;
    return page;
  }
}
