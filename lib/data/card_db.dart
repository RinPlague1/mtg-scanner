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

    Future<Object?> getJson(String url) async => jsonDecode(await (await get(url)).transform(utf8.decoder).join());

    // Where today's bulk file is. Read defensively: if this endpoint ever
    // changes shape, fall back to the list of all bulk files.
    var info = await getJson(_bulkInfoUrl);
    String? url = info is Map ? info['download_uri']?.toString() : null;
    if (url == null || url.isEmpty) {
      final list = await getJson('https://api.scryfall.com/bulk-data');
      final items = list is Map && list['data'] is List ? list['data'] as List : const [];
      final match = items.whereType<Map>().where((m) => m['type'] == 'default_cards').firstOrNull;
      info = match;
      url = match?['download_uri']?.toString();
    }
    if (url == null || url.isEmpty) {
      throw const FormatException("Scryfall didn't say where the card data file is");
    }
    final meta = info is Map ? info : const {};
    final total = (meta['size'] as num?)?.toDouble() ?? 0;

    // Set names come from the sets list (one small request).
    final setsJson = await getJson('https://api.scryfall.com/sets');
    final out = File('$path.tmp').openWrite();
    out.writeln('#v1\t${meta['updated_at'] ?? ''}');
    final sets = setsJson is Map && setsJson['data'] is List ? setsJson['data'] as List : const [];
    for (final m in sets.whereType<Map>()) {
      final code = m['code']?.toString();
      if (code == null || code.isEmpty) continue;
      final name = (m['name']?.toString() ?? code.toUpperCase()).replaceAll('\t', ' ');
      out.writeln('#set\t$code\t$name');
    }

    final res = await get(url);
    var seen = 0.0;
    var lastSent = 0.0;
    var written = 0;
    // The file is one big JSON array. Cut it into card objects as it streams
    // in (it may or may not have one card per line), so it never has to
    // fit in memory.
    final chars = res.transform(utf8.decoder).map((chunk) {
      seen += chunk.length;
      return chunk;
    });
    await for (final obj in splitJsonArray(chars)) {
      String? row;
      try {
        final card = jsonDecode(obj);
        // One odd card shouldn't stop the whole download.
        if (card is Map<String, dynamic> && card['id'] != null && card['name'] != null) row = encodeCardRow(card);
      } catch (_) {
        row = null;
      }
      if (row != null) {
        out.writeln(row);
        written++;
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

/// Splits a streamed JSON array (`[ {...}, {...} ]`) into the text of each
/// top-level object, whatever the line breaks and however the chunks fall.
Stream<String> splitJsonArray(Stream<String> chunks) async* {
  var depth = 0; // 1 = inside the array, 2+ = inside an object
  var inString = false;
  var escaped = false;
  final buf = StringBuffer();
  await for (final chunk in chunks) {
    var start = -1; // where the current object's text begins in this chunk
    if (depth >= 2) start = 0;
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true; // backslash
        } else if (c == 0x22) {
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B || c == 0x5B) {
        // { or [
        if (depth == 1 && c == 0x7B) start = i;
        depth++;
      } else if (c == 0x7D || c == 0x5D) {
        // } or ]
        depth--;
        if (depth == 1 && c == 0x7D && start >= 0) {
          buf.write(chunk.substring(start, i + 1));
          yield buf.toString();
          buf.clear();
          start = -1;
        }
      }
    }
    if (depth >= 2 && start >= 0) buf.write(chunk.substring(start));
  }
}
