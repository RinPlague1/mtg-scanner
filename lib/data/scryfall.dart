import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One printing of a card.
class CardPrint {
  final String id;
  final String name;
  final String setCode;
  final String setName;
  final String collectorNumber;
  final String rarity;
  final String? imageUrl;
  final String? priceEur;
  final String? priceEurFoil;
  final String? priceUsd;
  final String? priceUsdFoil;
  final List<String> finishes;

  /// Colour identity letters (W U B R G); empty = colourless. Older saved
  /// cards may not have it until "Refresh card details" runs.
  final List<String> colorIdentity;
  final String typeLine;

  /// Mana value; null when unknown.
  final double? cmc;

  bool get hasDetails => typeLine.isNotEmpty;

  CardPrint({
    required this.id,
    required this.name,
    required this.setCode,
    required this.setName,
    required this.collectorNumber,
    required this.rarity,
    this.imageUrl,
    this.priceEur,
    this.priceEurFoil,
    this.priceUsd,
    this.priceUsdFoil,
    this.finishes = const ['nonfoil'],
    this.colorIdentity = const [],
    this.typeLine = '',
    this.cmc,
  });

  factory CardPrint.fromScryfall(Map<String, dynamic> j) {
    String? img = (j['image_uris'] as Map?)?['normal'] as String?;
    final faces = j['card_faces'] as List?;
    if (img == null && faces != null && faces.isNotEmpty) {
      img = ((faces.first as Map)['image_uris'] as Map?)?['normal'] as String?;
    }
    final prices = (j['prices'] as Map?) ?? const {};
    var typeLine = j['type_line'] as String?;
    if (typeLine == null && faces != null && faces.isNotEmpty) {
      typeLine = (faces.first as Map)['type_line'] as String?;
    }
    return CardPrint(
      id: j['id'] as String,
      name: j['name'] as String,
      setCode: j['set'] as String,
      setName: (j['set_name'] as String?) ?? '',
      collectorNumber: j['collector_number'] as String,
      rarity: (j['rarity'] as String?) ?? '',
      imageUrl: img,
      priceEur: prices['eur'] as String?,
      priceEurFoil: prices['eur_foil'] as String?,
      priceUsd: prices['usd'] as String?,
      priceUsdFoil: prices['usd_foil'] as String?,
      finishes: ((j['finishes'] as List?) ?? const ['nonfoil']).cast<String>(),
      colorIdentity: ((j['color_identity'] as List?) ?? const []).cast<String>(),
      typeLine: typeLine ?? '',
      cmc: (j['cmc'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'set': setCode,
        'set_name': setName,
        'collector_number': collectorNumber,
        'rarity': rarity,
        'image_uris': {'normal': imageUrl},
        'prices': {
          'eur': priceEur,
          'eur_foil': priceEurFoil,
          'usd': priceUsd,
          'usd_foil': priceUsdFoil,
        },
        'finishes': finishes,
        'color_identity': colorIdentity,
        if (typeLine.isNotEmpty) 'type_line': typeLine,
        if (cmc != null) 'cmc': cmc,
      };

  /// Name match that tolerates double-faced "A // B" names.
  bool hasName(String n) {
    final a = n.toLowerCase();
    final full = name.toLowerCase();
    return full == a || full.split(' // ').contains(a) || a.split(' // ').contains(full);
  }
}

/// Minimal Scryfall client. Scryfall asks for a descriptive User-Agent, an
/// Accept header, and no more than ~10 requests/second.
class ScryfallClient {
  static const _base = 'https://api.scryfall.com';
  static const _headers = {
    'User-Agent': 'MTGDarkScanner/0.1 (personal project)',
    'Accept': 'application/json',
  };

  final http.Client _http;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  ScryfallClient([http.Client? client]) : _http = client ?? http.Client();

  Future<Map<String, dynamic>?> _get(String path, [Map<String, String>? query]) async {
    final wait = const Duration(milliseconds: 110) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('Scryfall ${res.statusCode}: ${res.body}', uri: uri);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final wait = const Duration(milliseconds: 110) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final uri = Uri.parse('$_base$path');
    final res = await _http
        .post(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpException('Scryfall ${res.statusCode}: ${res.body}', uri: uri);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Bulk lookup (POST /cards/collection), 75 identifiers per request.
  /// Identifiers: {'id': …} | {'set': …, 'collector_number': …} | {'name': …, 'set'?: …}.
  Future<List<CardPrint>> collection(List<Map<String, String>> identifiers) async {
    final out = <CardPrint>[];
    for (var i = 0; i < identifiers.length; i += 75) {
      final chunk = identifiers.sublist(i, i + 75 > identifiers.length ? identifiers.length : i + 75);
      final j = await _post('/cards/collection', {'identifiers': chunk});
      out.addAll((j['data'] as List).map((e) => CardPrint.fromScryfall(e as Map<String, dynamic>)));
    }
    return out;
  }

  /// Name suggestions for a search box.
  Future<List<String>> autocomplete(String q) async {
    if (q.trim().length < 2) return [];
    final j = await _get('/cards/autocomplete', {'q': q.trim()});
    return ((j?['data'] as List?) ?? const []).cast<String>();
  }

  Future<CardPrint?> bySetAndNumber(String set, String number) async {
    final j = await _get('/cards/${Uri.encodeComponent(set)}/${Uri.encodeComponent(number)}');
    return j == null ? null : CardPrint.fromScryfall(j);
  }

  Future<CardPrint?> named(String name, {String? set, bool fuzzy = false}) async {
    final q = <String, String>{fuzzy ? 'fuzzy' : 'exact': name, if (set != null) 'set': set};
    final j = await _get('/cards/named', q);
    return j == null ? null : CardPrint.fromScryfall(j);
  }

  /// All printings of a card, newest first.
  Future<List<CardPrint>> printings(String exactName) async {
    final j = await _get('/cards/search', {
      'q': '!"$exactName" include:extras',
      'unique': 'prints',
      'order': 'released',
      'dir': 'desc',
    });
    if (j == null) return [];
    return (j['data'] as List)
        .map((e) => CardPrint.fromScryfall(e as Map<String, dynamic>))
        .toList();
  }

  Future<File> _cardNamesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/card-names.json');
  }

  /// Size in bytes of the downloaded name list, or null if there isn't one.
  Future<int?> cardNamesSize() async {
    final f = await _cardNamesFile();
    return await f.exists() ? await f.length() : null;
  }

  /// Remove the downloaded name list (when switching to online matching).
  Future<void> deleteCardNames() async {
    final f = await _cardNamesFile();
    if (await f.exists()) await f.delete();
  }

  /// Every English card name, cached on disk and refreshed weekly.
  Future<List<String>> cardNames() async {
    final file = await _cardNamesFile();
    if (await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age < const Duration(days: 7)) {
        return (jsonDecode(await file.readAsString()) as List).cast<String>();
      }
    }
    try {
      final j = await _get('/catalog/card-names');
      final names = (j!['data'] as List).cast<String>();
      await file.writeAsString(jsonEncode(names));
      return names;
    } catch (_) {
      if (await file.exists()) {
        return (jsonDecode(await file.readAsString()) as List).cast<String>();
      }
      rethrow;
    }
  }
}
