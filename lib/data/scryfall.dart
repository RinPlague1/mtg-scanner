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
  });

  factory CardPrint.fromScryfall(Map<String, dynamic> j) {
    String? img = (j['image_uris'] as Map?)?['normal'] as String?;
    final faces = j['card_faces'] as List?;
    if (img == null && faces != null && faces.isNotEmpty) {
      img = ((faces.first as Map)['image_uris'] as Map?)?['normal'] as String?;
    }
    final prices = (j['prices'] as Map?) ?? const {};
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

  /// Every English card name, cached on disk and refreshed weekly.
  Future<List<String>> cardNames() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/card-names.json');
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
