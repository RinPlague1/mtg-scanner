/// Turns raw OCR text from the title and collector-line crops into candidate
/// card names and a (set code, collector number) pair.
class CardTextParser {
  /// Candidate title strings, best first. OCR of a title crop usually yields
  /// one line, but may also pick up stray fragments of the frame or type line.
  static List<String> nameCandidates(List<String> lines) {
    final out = <String>[];
    for (final raw in lines) {
      final cleaned = cleanName(raw);
      if (cleaned.replaceAll(' ', '').length >= 3) out.add(cleaned);
    }
    // Longer lines first: real titles beat 2-3 letter noise.
    out.sort((a, b) => b.length.compareTo(a.length));
    return out;
  }

  /// Keep letters (including accented), digits, spaces and the punctuation
  /// that appears in card names; normalise common OCR confusions.
  static String cleanName(String s) {
    var t = s
        .replaceAll('’', "'")
        .replaceAll('`', "'")
        .replaceAll('|', 'l')
        .replaceAll(RegExp(r"[^A-Za-zÀ-ÿ0-9 ,'\-!?&/.]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // A trailing run of digits / single letters is usually the mana cost
    // leaking into the crop.
    t = t.replaceAll(RegExp(r'(\s+[0-9XWUBRGC]{1,2})+$'), '');
    return t.trim();
  }

  /// Parses the collector line, e.g.
  ///   "0107 M" / "DMU • EN"          (2022+ frames)
  ///   "107/281 R" / "M20 • EN"       (M15 – 2021 frames)
  static SetInfo? setInfo(List<String> lines) {
    String? number;
    String? setCode;
    // Collector number: 1-4 digits, optional letter suffix, optional /total,
    // followed by a rarity letter.
    final numRe = RegExp(r'\b(\d{1,4}[a-z]?)(?:\s*/\s*\d{1,4})?\s+[CURMSLTPcurmsltp]\b');
    // Set code: 3-5 alphanumerics then a bullet-ish separator then language.
    final setRe = RegExp(r'\b([A-Z0-9]{3,5})\s*[•·*.,:-]?\s*(EN|DE|FR|IT|ES|PT|JA|JP|KO|RU|ZHS|ZHT|CS|CT|PH)\b');
    for (final raw in lines) {
      final line = raw.replaceAll('O', '0').replaceAll(RegExp(r'[Il|]'), '1');
      number ??= numRe.firstMatch(line)?.group(1);
      final m = setRe.firstMatch(raw.toUpperCase());
      if (m != null && setCode == null) {
        final code = m.group(1)!;
        // Must contain a letter; pure digits are the collector number.
        if (RegExp(r'[A-Z]').hasMatch(code)) setCode = code;
      }
    }
    // Fallback: a bare number line like "0107" with no rarity letter.
    if (number == null) {
      for (final raw in lines) {
        final m = RegExp(r'^\s*(\d{1,4})\s*(?:/\s*\d{1,4})?\s*$').firstMatch(raw);
        if (m != null) {
          number = m.group(1);
          break;
        }
      }
    }
    if (number == null && setCode == null) return null;
    // Scryfall collector numbers have no leading zeros ("0107" -> "107").
    final cn = number?.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return SetInfo(setCode?.toLowerCase(), cn);
  }
}

class SetInfo {
  final String? setCode; // lower-case Scryfall set code
  final String? collectorNumber;
  const SetInfo(this.setCode, this.collectorNumber);
  bool get complete => setCode != null && collectorNumber != null;

  @override
  bool operator ==(Object other) =>
      other is SetInfo && other.setCode == setCode && other.collectorNumber == collectorNumber;
  @override
  int get hashCode => Object.hash(setCode, collectorNumber);
  @override
  String toString() => '${setCode ?? '?'} #${collectorNumber ?? '?'}';
}
