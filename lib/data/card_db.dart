/// Offline card data: every paper printing's name, set, collector number,
/// type, mana cost and prices, downloaded once from Scryfall's bulk data and
/// stored compactly on the phone (no images: those load from Scryfall when
/// shown, small ones for lists and full size for details).
///
/// With it, scans, deck details and printing lists are answered on the
/// phone instead of waiting on Scryfall. Anything missing (cards newer than
/// the download) still goes online.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'scryfall.dart';

const _bulkInfoUrl = 'https://api.scryfall.com/bulk-data/default-cards';
const _userAgent = 'MTGDarkScanner/0.1 (personal project)';

/// Set types that aren't the "normal" printing of a card: the default
/// printing for a name avoids these when it can.
const _specialSetTypes = {'promo', 'token', 'memorabilia', 'funny', 'alchemy', 'minigame', 'vanguard'};

/// One Scryfall card JSON → one tab-separated row, or null to skip it
/// (digital-only cards). Columns:
/// id, name, set, number, rarity, eur, eurFoil, usd, usdFoil, finishes,
/// colour identity, type line, mana value, mana cost, released, flags, image.
String? encodeCardRow(Map<String, dynamic> j) {
  if (j['digital'] == true) return null;
  final games = (j['games'] as List?)?.cast<String>();
  if (games != null && games.isNotEmpty && !games.contains('paper')) return null;
  final faces = j['card_faces'] as List?;
  final first = faces != null && faces.isNotEmpty ? faces.first as Map : const {};
  final prices = (j['prices'] as Map?) ?? const {};
  var mana = j['mana_cost'] as String?;
  if ((mana == null || mana.isEmpty) && faces != null) {
    mana = faces.map((f) => (f as Map)['mana_cost'] as String? ?? '').where((m) => m.isNotEmpty).join(' // ');
  }
  final hasImage = j['image_uris'] != null || first['image_uris'] != null;
  final special = j['promo'] == true || _specialSetTypes.contains(j['set_type']) || j['oversized'] == true;
  String clean(Object? v) => (v?.toString() ?? '').replaceAll('\t', ' ').replaceAll('\n', ' ');
  final cmc = (j['cmc'] as num?)?.toDouble();
  return [
    j['id'],
    j['name'],
    j['set'],
    j['collector_number'],
    j['rarity'] ?? '',
    prices['eur'] ?? '',
    prices['eur_foil'] ?? '',
    prices['usd'] ?? '',
    prices['usd_foil'] ?? '',
    ((j['finishes'] as List?) ?? const ['nonfoil']).join(','),
    ((j['color_identity'] as List?) ?? const []).join(),
    j['type_line'] ?? first['type_line'] ?? '',
    cmc == null ? '' : (cmc == cmc.roundToDouble() ? cmc.toInt().toString() : cmc.toString()),
    mana ?? '',
    j['released_at'] ?? '',
    special ? 's' : '',
    hasImage ? '1' : '0',
  ].map(clean).join('\t');
}

/// Scryfall image link for a printing, worked out from its id (so the
/// download doesn't have to store links). [size]: small, normal or large.
String scryfallImageUrl(String id, {String size = 'normal'}) =>
    'https://cards.scryfall.io/$size/front/${id[0]}/${id[1]}/$id.jpg';

/// Swap the size in a Scryfall image link (lists use small images, details
/// large ones). Other links are returned unchanged.
String imageAtSize(String url, String size) =>
    url.contains('cards.scryfall.io/') ? url.replaceFirst(RegExp(r'/(small|normal|large)/'), '/$size/') : url;

String _codeKey(String set, String number) => '${set.toLowerCase()}|${number.toLowerCase()}';

class CardDb {
  final List<String> _rows;
  final Map<String, String> setNames;
  final Map<String, int> _byCode;
  final Map<String, int> _byId;

  /// nameKey → rows, preferred printing first.
  final Map<String, List<int>> _byName;
  final String updatedAt;

  CardDb._(this._rows, this.setNames, this._byCode, this._byId, this._byName, this.updatedAt);

  int get printingCount => _rows.length;
  int get cardCount => _byName.length;

  /// Every card name (front-face keys aren't names, so use the rows).
  List<String> get names => [for (final rows in _byName.values) _rows[rows.first].split('\t')[1]];

  /// Builds the indexes from the stored file text. Run in an isolate for
  /// the full download (see [loadFile]).
  factory CardDb.parse(String text) {
    final rows = <String>[];
    final sets = <String, String>{};
    var updated = '';
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      if (line.startsWith('#set\t')) {
        final p = line.split('\t');
        if (p.length >= 3) sets[p[1]] = p[2];
      } else if (line.startsWith('#v1\t')) {
        updated = line.substring(4);
      } else if (!line.startsWith('#')) {
        rows.add(line);
      }
    }
    final byCode = <String, int>{};
    final byId = <String, int>{};
    final byName = <String, List<int>>{};
    final released = <int, String>{};
    final special = <int, bool>{};
    for (var i = 0; i < rows.length; i++) {
      final p = rows[i].split('\t');
      if (p.length < 17) continue;
      byCode[_codeKey(p[2], p[3])] = i;
      byId[p[0]] = i;
      byName.putIfAbsent(nameKey(p[1]), () => []).add(i);
      released[i] = p[14];
      special[i] = p[15] == 's';
    }
    // Preferred printing first: normal printings before promos and the like,
    // then newest first.
    for (final list in byName.values) {
      list.sort((a, b) {
        final sa = special[a]!, sb = special[b]!;
        if (sa != sb) return sa ? 1 : -1;
        return released[b]!.compareTo(released[a]!);
      });
    }
    return CardDb._(rows, sets, byCode, byId, byName, updated);
  }

  CardPrint _at(int i) {
    final p = _rows[i].split('\t');
    String? s(int k) => p[k].isEmpty ? null : p[k];
    return CardPrint(
      id: p[0],
      name: p[1],
      setCode: p[2],
      setName: setNames[p[2]] ?? p[2].toUpperCase(),
      collectorNumber: p[3],
      rarity: p[4],
      priceEur: s(5),
      priceEurFoil: s(6),
      priceUsd: s(7),
      priceUsdFoil: s(8),
      finishes: p[9].isEmpty ? const ['nonfoil'] : p[9].split(','),
      colorIdentity: p[10].isEmpty ? const [] : p[10].split(''),
      typeLine: p[11],
      cmc: double.tryParse(p[12]),
      manaCost: p[13],
      imageUrl: p[16] == '1' ? scryfallImageUrl(p[0]) : null,
    );
  }

  /// By Scryfall id (ManaBox and Moxfield exports include it).
  CardPrint? byId(String id) {
    final i = _byId[id.toLowerCase()];
    return i == null ? null : _at(i);
  }

  /// By set code + collector number ("dft", "194"); tolerates leading zeros
  /// read from the card ("0194").
  CardPrint? byCode(String set, String number) {
    var i = _byCode[_codeKey(set, number)];
    if (i == null) {
      final trimmed = number.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (trimmed != number) i = _byCode[_codeKey(set, trimmed)];
    }
    return i == null ? null : _at(i);
  }

  /// The preferred printing of a card name, or the one from [set].
  CardPrint? named(String name, {String? set}) {
    final rows = _byName[nameKey(name)];
    if (rows == null) return null;
    if (set != null) {
      final s = set.toLowerCase();
      for (final i in rows) {
        if (_rows[i].split('\t')[2] == s) return _at(i);
      }
      return null;
    }
    return _at(rows.first);
  }

  /// All printings of a card, newest first.
  List<CardPrint> printings(String name) {
    final rows = _byName[nameKey(name)];
    if (rows == null) return const [];
    final list = [for (final i in rows) _at(i)];
    final released = {for (final i in rows) _rows[i].split('\t')[0]: _rows[i].split('\t')[14]};
    list.sort((a, b) => released[b.id]!.compareTo(released[a.id]!));
    return list;
  }

  static Future<File> file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/card-data.tsv');
  }

  static Future<CardDb?> loadFile() async {
    final f = await file();
    if (!await f.exists()) return null;
    final path = f.path;
    return Isolate.run(() => CardDb.parse(File(path).readAsStringSync()));
  }
}

/// Holds the offline card data and runs its download.
class CardDbStore extends ChangeNotifier {
  CardDb? db;
  bool loading = false;

  /// 0–1 while downloading, null otherwise.
  double? progress;
  String? error;
  int? fileBytes;
  DateTime? downloadedAt;

  bool get downloading => progress != null;
  bool get isStale => downloadedAt != null && DateTime.now().difference(downloadedAt!) > const Duration(days: 7);

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final f = await CardDb.file();
      if (await f.exists()) {
        fileBytes = await f.length();
        downloadedAt = await f.lastModified();
        db = await CardDb.loadFile();
      }
    } catch (e) {
      error = 'Could not read the card data: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    if (downloading) return;
    progress = 0;
    error = null;
    notifyListeners();
    final f = await CardDb.file();
    final port = ReceivePort();
    final done = Completer<void>();
    Isolate? iso;
    try {
      iso = await Isolate.spawn(_downloadMain, [port.sendPort, f.path],
          onError: port.sendPort, onExit: port.sendPort);
    } catch (e) {
      error = 'Download failed: $e';
      done.complete();
    }
    port.listen((msg) {
      if (msg == null) {
        // The download isolate ended without saying why.
        if (!done.isCompleted) {
          error ??= 'Download stopped unexpectedly';
          done.complete();
        }
      } else if (msg is List) {
        error = 'Download failed: ${msg.first}';
        if (!done.isCompleted) done.complete();
      } else if (msg is double) {
        progress = msg;
        notifyListeners();
      } else if (msg == 'done') {
        if (!done.isCompleted) done.complete();
      } else if (msg is String) {
        error = msg;
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
    port.close();
    iso?.kill();
    progress = null;
    if (error == null) await load();
    notifyListeners();
  }

  Future<void> delete() async {
    final f = await CardDb.file();
    if (await f.exists()) await f.delete();
    db = null;
    fileBytes = null;
    downloadedAt = null;
    notifyListeners();
  }
}

/// Download isolate: streams Scryfall's "Default Cards" bulk file (one card
/// per line), keeps the columns we need, and writes the compact file.
Future<void> _downloadMain(List<Object?> args) async {
  final send = args[0] as SendPort;
  final path = args[1] as String;
  final client = HttpClient()..userAgent = _userAgent;
  try {
    Future<HttpClientResponse> get(String url) async {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} for $url');
      return res;
    }

    final info = jsonDecode(await (await get(_bulkInfoUrl)).transform(utf8.decoder).join()) as Map<String, dynamic>;
    final url = info['download_uri'] as String;
    final total = (info['size'] as num?)?.toDouble() ?? 0;

    // Set names come from the sets list (one small request).
    final setsJson =
        jsonDecode(await (await get('https://api.scryfall.com/sets')).transform(utf8.decoder).join()) as Map;
    final out = File('$path.tmp').openWrite();
    out.writeln('#v1\t${info['updated_at'] ?? ''}');
    for (final s in (setsJson['data'] as List)) {
      final m = s as Map;
      out.writeln('#set\t${m['code']}\t${(m['name'] as String).replaceAll('\t', ' ')}');
    }

    final res = await get(url);
    var seen = 0.0;
    var lastSent = 0.0;
    var written = 0;
    await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
      seen += line.length + 1;
      var t = line.trim();
      if (t.endsWith(',')) t = t.substring(0, t.length - 1);
      if (t.startsWith('{')) {
        final row = encodeCardRow(jsonDecode(t) as Map<String, dynamic>);
        if (row != null) {
          out.writeln(row);
          written++;
        }
      }
      if (total > 0 && seen / total - lastSent >= 0.01) {
        lastSent = seen / total;
        send.send(lastSent.clamp(0.0, 0.99));
      }
    }
    await out.flush();
    await out.close();
    if (written < 1000) {
      await File('$path.tmp').delete();
      throw const FormatException('the file from Scryfall had an unexpected layout');
    }
    await File('$path.tmp').rename(path);
    send.send('done');
  } catch (e) {
    send.send('Download failed: $e');
  } finally {
    client.close(force: true);
  }
}
