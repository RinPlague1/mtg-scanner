import 'dart:math' as math;

/// Offline fuzzy matcher over every English card name (from Scryfall's
/// /catalog/card-names). Corrects OCR slips like "Sheo1dred, the Apocalyps"
/// without a network round-trip, and rejects garbage reads outright.
class NameIndex {
  final List<String> _names; // display names (front face for DFCs)
  final List<String> _keys; // normalised
  final Map<int, List<int>> _byLength = {};
  final Map<String, int> _exact = {};

  NameIndex(Iterable<String> catalog)
      : _names = [],
        _keys = [] {
    for (final full in catalog) {
      // Index both faces of "Front // Back" and the full string.
      final faces = full.split(' // ');
      final variants = {full, ...faces};
      for (final v in variants) {
        final k = normalise(v);
        if (k.isEmpty || _exact.containsKey(k)) continue;
        final idx = _names.length;
        _names.add(full);
        _keys.add(k);
        _exact[k] = idx;
        _byLength.putIfAbsent(k.length, () => []).add(idx);
      }
    }
  }

  int get size => _names.length;

  static String normalise(String s) {
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final r in lower.runes) {
      final ch = String.fromCharCode(r);
      final mapped = _fold[ch] ?? ch;
      final c = mapped.codeUnitAt(0);
      if ((c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39)) {
        b.write(mapped);
      } else if (mapped == ' ' || mapped == '-') {
        b.write(' ');
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Best match for an OCR'd title, or null if nothing is close enough.
  NameMatch? match(String query, {double minScore = 0.78}) {
    final q = normalise(query);
    if (q.length < 3) return null;
    final exact = _exact[q];
    if (exact != null) return NameMatch(_names[exact], 1.0);

    final maxDist = (q.length * (1 - minScore)).floor();
    var bestIdx = -1;
    var bestScore = 0.0;
    for (var len = q.length - maxDist; len <= q.length + maxDist; len++) {
      final bucket = _byLength[len];
      if (bucket == null) continue;
      for (final idx in bucket) {
        final d = levenshtein(q, _keys[idx], maxDist);
        if (d > maxDist) continue;
        final score = 1 - d / math.max(q.length, _keys[idx].length);
        if (score > bestScore) {
          bestScore = score;
          bestIdx = idx;
        }
      }
    }
    // OCR often truncates long titles at the crop edge: accept a confident
    // prefix match too ("Sheoldred, the Apoc" -> "Sheoldred, the Apocalypse").
    if (bestScore < minScore && q.length >= 8) {
      for (var i = 0; i < _keys.length; i++) {
        final k = _keys[i];
        if (k.length > q.length && k.startsWith(q)) {
          final score = 0.8 + 0.2 * q.length / k.length;
          if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
          }
        }
      }
    }
    if (bestIdx < 0 || bestScore < minScore) return null;
    return NameMatch(_names[bestIdx], bestScore);
  }

  /// Bounded Levenshtein distance; returns > [maxDist] as soon as it's
  /// certain to exceed it.
  static int levenshtein(String a, String b, int maxDist) {
    if ((a.length - b.length).abs() > maxDist) return maxDist + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= b.length; j++) {
        final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
        final v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > maxDist) return maxDist + 1;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }

  static const _fold = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c', 'æ': 'ae',
  };
}

class NameMatch {
  final String name;
  final double score;
  const NameMatch(this.name, this.score);
}
