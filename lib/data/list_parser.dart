/// Parses card lists from TXT (deck lists, "1 Sol Ring") and CSV (ManaBox,
/// Moxfield, Deckbox, Archidekt, and anything with a Name column).
library;

import 'models.dart';

class ImportLine {
  final int qty;
  final String name;
  final String? setCode;
  final String? collectorNumber;
  final String? scryfallId;
  final bool foil;
  final CardCondition condition;
  final bool commander;

  /// Section the line came from: main, commander, sideboard, maybeboard…
  final String section;

  const ImportLine({
    required this.qty,
    required this.name,
    this.setCode,
    this.collectorNumber,
    this.scryfallId,
    this.foil = false,
    this.condition = CardCondition.nm,
    this.commander = false,
    this.section = 'main',
  });
}

class ParsedList {
  final List<ImportLine> lines;

  /// Lines that couldn't be read, with their 1-based line number.
  final List<String> problems;
  final bool wasCsv;

  const ParsedList(this.lines, this.problems, {required this.wasCsv});

  int get cardCount => lines.fold(0, (s, l) => s + l.qty);
}

ParsedList parseCardList(String text, {String? fileName}) {
  final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceFirst('﻿', '');
  final isCsv = (fileName?.toLowerCase().endsWith('.csv') ?? false) || _looksLikeCsv(clean);
  return isCsv ? parseCsv(clean) : parseTxt(clean);
}

bool _looksLikeCsv(String text) {
  final first = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final cols = splitCsvLine(first).map((c) => c.trim().toLowerCase()).toList();
  return cols.length >= 2 && cols.any((c) => _nameHeaders.contains(c));
}

// ───────────────────────── TXT ─────────────────────────

const _sectionNames = {
  'commander': 'commander',
  'commanders': 'commander',
  'companion': 'companion',
  'deck': 'main',
  'main': 'main',
  'mainboard': 'main',
  'main deck': 'main',
  'sideboard': 'sideboard',
  'side': 'sideboard',
  'maybeboard': 'maybeboard',
  'considering': 'maybeboard',
  'tokens': 'tokens',
};

final _txtLine = RegExp(
  r'^(?:(\d+)\s*[xX]?\s+)?' // quantity, optional "x"
  r'(.+?)' // name
  r'(?:\s+\(([A-Za-z0-9]{2,6})\)(?:\s+([A-Za-z0-9★\-/]+))?)?' // (SET) 123
  r'$',
);

ParsedList parseTxt(String text) {
  final lines = <ImportLine>[];
  final problems = <String>[];
  var section = 'main';
  final all = text.split('\n');
  for (var i = 0; i < all.length; i++) {
    var raw = all[i].trim();
    if (raw.isEmpty || raw.startsWith('#')) continue;

    // Section headers: "Commander", "// Sideboard", "SIDEBOARD:", "Deck (99)".
    final header = raw
        .replaceFirst(RegExp(r'^//\s*'), '')
        .replaceFirst(RegExp(r':$'), '')
        .replaceFirst(RegExp(r'\s*\(\d+\)$'), '')
        .trim()
        .toLowerCase();
    if (_sectionNames.containsKey(header)) {
      section = _sectionNames[header]!;
      continue;
    }
    if (raw.startsWith('//')) continue; // other comments

    var foil = false;
    var commander = section == 'commander';

    // Archidekt style tags: [Commander{top}], [Ramp]
    final tags = RegExp(r'\[([^\]]*)\]').allMatches(raw).map((m) => m.group(1)!.toLowerCase());
    if (tags.any((t) => t.contains('commander'))) commander = true;
    var lineSection = section;
    if (tags.any((t) => t.contains('maybeboard'))) lineSection = 'maybeboard';
    if (tags.any((t) => t.contains('sideboard'))) lineSection = 'sideboard';
    raw = raw.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    // Moxfield-style markers: *F* foil, *E* etched, ^tags^.
    if (RegExp(r'\*[FE]\*').hasMatch(raw)) foil = true;
    raw = raw
        .replaceAll(RegExp(r'\*[A-Z]\*'), '')
        .replaceAll(RegExp(r'\^[^\^]*\^'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final m = _txtLine.firstMatch(raw);
    if (m == null || m.group(2)!.trim().isEmpty) {
      problems.add('Line ${i + 1}: "${all[i].trim()}"');
      continue;
    }
    final qty = int.tryParse(m.group(1) ?? '1') ?? 1;
    if (qty <= 0) continue;
    lines.add(ImportLine(
      qty: qty,
      name: m.group(2)!.trim(),
      setCode: m.group(3)?.toLowerCase(),
      collectorNumber: m.group(4),
      foil: foil,
      commander: commander,
      section: commander ? 'commander' : lineSection,
    ));
  }
  return ParsedList(lines, problems, wasCsv: false);
}

// ───────────────────────── CSV ─────────────────────────

const _nameHeaders = {'name', 'card name', 'card', 'card_name'};
const _qtyHeaders = {'count', 'quantity', 'qty', 'amount', 'tradelist count'};
const _setHeaders = ['set code', 'edition code', 'set', 'edition', 'setcode'];
const _numberHeaders = {'collector number', 'collector_number', 'card number', 'number', 'collector #', 'cn'};
const _foilHeaders = {'foil', 'finish', 'printing', 'foil/etched'};
const _conditionHeaders = {'condition', 'cond'};
const _idHeaders = {'scryfall id', 'scryfall_id', 'scryfallid', 'scryfall uuid'};

/// Splits one CSV line, honouring quotes ("a, b" and "" escapes).
List<String> splitCsvLine(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',' || (ch == ';' && !line.contains(','))) {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString());
  return out;
}

/// Splits CSV text into records, keeping newlines inside quoted fields.
List<String> _csvRecords(String text) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') quoted = !quoted;
    if (ch == '\n' && !quoted) {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  if (cur.isNotEmpty) out.add(cur.toString());
  return out.where((l) => l.trim().isNotEmpty).toList();
}

ParsedList parseCsv(String text) {
  final records = _csvRecords(text);
  if (records.isEmpty) return const ParsedList([], ['The file is empty'], wasCsv: true);

  final header = splitCsvLine(records.first).map((h) => h.trim().toLowerCase()).toList();
  int col(Iterable<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iName = col(_nameHeaders);
  if (iName < 0) {
    return ParsedList([], ['No "Name" column found. Columns were: ${header.join(', ')}'], wasCsv: true);
  }
  final iQty = col(_qtyHeaders);
  final iSet = col(_setHeaders);
  final iNum = col(_numberHeaders);
  final iFoil = col(_foilHeaders);
  final iCond = col(_conditionHeaders);
  final iId = col(_idHeaders);
  final iSection = col(['section', 'board', 'category']);

  final lines = <ImportLine>[];
  final problems = <String>[];
  for (var r = 1; r < records.length; r++) {
    final cells = splitCsvLine(records[r]);
    String? at(int i) {
      if (i < 0 || i >= cells.length) return null;
      final v = cells[i].trim();
      return v.isEmpty ? null : v;
    }

    final name = at(iName);
    if (name == null) {
      problems.add('Row ${r + 1}: no card name');
      continue;
    }
    final qty = int.tryParse(at(iQty) ?? '1') ?? 1;
    if (qty <= 0) continue;
    final foilText = (at(iFoil) ?? '').toLowerCase();
    final foil = const {'foil', 'etched', 'true', 'yes', '1', 'y'}.contains(foilText);
    final section = (at(iSection) ?? 'main').toLowerCase();
    final commander = section.contains('commander');
    var set = at(iSet)?.toLowerCase();
    // "Edition" may hold a full set name on some sites; only keep short codes.
    if (set != null && (set.length > 6 || set.contains(' '))) set = null;
    lines.add(ImportLine(
      qty: qty,
      name: name,
      setCode: set,
      collectorNumber: at(iNum),
      scryfallId: at(iId),
      foil: foil,
      condition: CardCondition.parse(at(iCond)),
      commander: commander,
      section: commander
          ? 'commander'
          : section.contains('maybe')
              ? 'maybeboard'
              : (section.contains('side') ? 'sideboard' : 'main'),
    ));
  }
  return ParsedList(lines, problems, wasCsv: true);
}
