import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';
import 'geometry.dart';

/// Finds the true card edges near the on-screen guide.
///
/// Why typical scanners struggle with black cards: they run Canny on a
/// grayscale image and look for the biggest 4-sided contour. A black border
/// (~15/255) on a dark mat (~25/255) is a difference of a few grey levels,
/// far below any sensible Canny threshold, so the contour is never closed.
///
/// What this does instead:
///  1. Works in **log intensity, per colour channel**. A step from 15 to 25 is
///     the same *ratio* as 150 to 250, so in log space a black border on a
///     dark mat is as strong an edge as a white border on a wooden table.
///     Taking the max over R, G and B also catches borders that differ from a
///     mat in hue but not brightness (e.g. a navy or green mat).
///  2. Never needs a closed contour. The guide tells us roughly where each
///     side is, so each side is a 1-D search for a straight line in a narrow
///     band, averaging ~200 pixels along the line. Averaging is what lets a
///     faint edge rise far above sensor noise and cloth texture.
///  3. Estimates one rotation for the whole card (sides of a rectangle share
///     it), so a slanted line that clips a strong inner edge can't win.
///  4. Picks the **outermost** significant edge on each side, so the strong
///     frame / art-box edges inside the card don't steal the match.
///  5. Falls back to the guide for any side it can't see, so a scan still
///     happens; the crop regions are padded to tolerate that.
///  6. Scores a candidate line by a low percentile of the edge strength along
///     it, not the mean: a real card edge runs the whole side, while a busy
///     playmat (flames, foil art) only has short strong streaks.
///  7. Keeps a few candidate edges per side and picks the combination that
///     forms a 63×88 card shape, preferring the outermost edges. A pattern
///     edge on the mat outside the card no longer drags the outline off.
class EdgeRefiner {
  /// How far either side of the guide edge to search, as a fraction of the
  /// guide's size in that direction.
  final double band;

  /// Global rotation search range / step in degrees.
  final double maxAngle;
  final double angleStep;

  /// Minimum significance of an edge, in log-gradient units above the floor.
  final double minContrast;

  const EdgeRefiner({
    this.band = 0.12,
    this.maxAngle = 6,
    this.angleStep = 0.5,
    this.minContrast = 0.07,
  });

  RefineResult refine(RgbImage img, Box guideNorm) {
    final w = img.width, h = img.height;
    final maps = _edgeMaps(img);
    final g = guideNorm.toPixels(w.toDouble(), h.toDouble());

    final bands = <_Side, _Band>{};
    for (final side in _Side.values) {
      final hor = side == _Side.top || side == _Side.bottom;
      final gPos = switch (side) {
        _Side.top => g.top,
        _Side.bottom => g.bottom,
        _Side.left => g.left,
        _Side.right => g.right,
      };
      final d = band * (hor ? g.height : g.width);
      final spanLo = hor ? g.left + 0.15 * g.width : g.top + 0.15 * g.height;
      final spanHi = hor ? g.right - 0.15 * g.width : g.bottom - 0.15 * g.height;
      final lim = hor ? h : w;
      final lo = math.max(1, (gPos - d).ceil());
      final hi = math.min(lim - 2, (gPos + d).floor());
      bands[side] = _Band(side, hor, lo, hi, spanLo, spanHi, gPos);
    }

    // 1) Global rotation: maximise the sum of each side's strongest line.
    var bestAngle = 0.0;
    var bestTotal = -1.0;
    for (var a = -maxAngle; a <= maxAngle + 1e-9; a += angleStep) {
      final t = math.tan(a * math.pi / 180);
      var total = 0.0;
      for (final b in bands.values) {
        final prof = _profile(maps, w, h, b, [b.horizontal ? t : -t]);
        if (prof.scores.isEmpty) continue;
        total += _max(prof.scores) - _percentile(prof.scores, 0.15);
      }
      if (total > bestTotal) {
        bestTotal = total;
        bestAngle = a;
      }
    }

    // 2) Per side: allow +-1 deg around the global angle (mild perspective)
    //    and keep up to four significant edges, outermost first. The guide
    //    edge is always the last option, for a side that isn't visible.
    final cands = <_Side, List<_Cand>>{};
    for (final b in bands.values) {
      final sgn = b.horizontal ? 1.0 : -1.0;
      final slopes = [-1.0, -0.5, 0.0, 0.5, 1.0]
          .map((d) => math.tan((sgn * bestAngle + d) * math.pi / 180))
          .toList();
      final prof = _profile(maps, w, h, b, slopes);
      final outerFirst = b.side == _Side.top || b.side == _Side.left;
      final mid = (b.spanLo + b.spanHi) / 2;
      cands[b.side] = [
        for (final pick in _significantPeaks(prof.scores, outerFirst))
          _Cand(_Line(prof.positions[pick.index].toDouble(), prof.slopes[pick.index], mid), pick.significance),
        _Cand(_Line(b.guidePos, math.tan(sgn * bestAngle * math.pi / 180), mid), null),
      ];
    }

    Quad quadOf(_Cand t, _Cand bo, _Cand l, _Cand r) => Quad([
          _intersect(t.line, l.line),
          _intersect(t.line, r.line),
          _intersect(bo.line, r.line),
          _intersect(bo.line, l.line),
        ]);

    // 3) Choose the combination that makes a card-shaped rectangle of about
    //    guide size: most real edges first, then outermost, then best shape.
    final gw = g.width, gh = g.height;
    final ts = cands[_Side.top]!, bs = cands[_Side.bottom]!, ls = cands[_Side.left]!, rs = cands[_Side.right]!;
    Quad? bestQuad;
    var bestFound = -1, bestRank = 1 << 30;
    var bestErr = double.infinity;
    for (var i = 0; i < ts.length; i++) {
      for (var j = 0; j < bs.length; j++) {
        for (var k = 0; k < ls.length; k++) {
          for (var m = 0; m < rs.length; m++) {
            final q = quadOf(ts[i], bs[j], ls[k], rs[m]);
            final qw = (q.topWidth + q.bottomWidth) / 2;
            final qh = (q.leftHeight + q.rightHeight) / 2;
            if (qh <= 0) continue;
            final err = ((qw / qh) - kCardAspect).abs() / kCardAspect;
            if (err > 0.05 || qw < 0.6 * gw || qw > 1.3 * gw || qh < 0.6 * gh || qh > 1.3 * gh) continue;
            final found = [ts[i], bs[j], ls[k], rs[m]].where((c) => c.significance != null).length;
            final rank = i + j + k + m;
            final better = found > bestFound ||
                (found == bestFound && (rank < bestRank || (rank == bestRank && err < bestErr)));
            if (better) {
              bestQuad = q;
              bestFound = found;
              bestRank = rank;
              bestErr = err;
            }
          }
        }
      }
    }

    // No card-shaped combination: fall back to the outermost edge per side,
    // checked by the looser sanity test below.
    final quad = bestQuad ?? quadOf(ts.first, bs.first, ls.first, rs.first);
    final foundSides = bestQuad != null
        ? bestFound
        : [ts.first, bs.first, ls.first, rs.first].where((c) => c.significance != null).length;

    // Sanity: a card is a 63x88 rectangle of roughly guide size. If the
    // result is badly off, trust the guide instead.
    final qw = (quad.topWidth + quad.bottomWidth) / 2;
    final qh = (quad.leftHeight + quad.rightHeight) / 2;
    final aspect = qh > 0 ? qw / qh : 0;
    final sane = qw > 0.6 * gw &&
        qw < 1.3 * gw &&
        qh > 0.6 * gh &&
        qh < 1.3 * gh &&
        (aspect - kCardAspect).abs() < 0.12 * kCardAspect;

    return RefineResult(
      quad: sane ? quad : Quad.fromBox(g),
      sidesFound: sane ? foundSides : 0,
      angleDegrees: bestAngle,
    );
  }

  // --- internals -----------------------------------------------------------

  static final Float64List _logLut = () {
    final l = Float64List(256);
    for (var i = 0; i < 256; i++) {
      l[i] = math.log(i + 8.0); // +8 stops sensor noise in near-black exploding
    }
    return l;
  }();

  /// |d/dx| and |d/dy| of 3x3-box-blurred log intensity, max over channels.
  static _EdgeMaps _edgeMaps(RgbImage img) {
    final w = img.width, h = img.height, n = w * h;
    final ex = Float32List(n), ey = Float32List(n);
    final lg = Float32List(n), bl = Float32List(n);
    for (var c = 0; c < 3; c++) {
      for (var i = 0; i < n; i++) {
        lg[i] = _logLut[img.data[i * 3 + c]];
      }
      // 3x3 box blur, edge-clamped
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var s = 0.0;
          for (var dy = -1; dy <= 1; dy++) {
            final yy = (y + dy).clamp(0, h - 1).toInt();
            for (var dx = -1; dx <= 1; dx++) {
              final xx = (x + dx).clamp(0, w - 1).toInt();
              s += lg[yy * w + xx];
            }
          }
          bl[y * w + x] = s / 9;
        }
      }
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          final gx = (bl[i + 1] - bl[i - 1]).abs();
          final gy = (bl[i + w] - bl[i - w]).abs();
          if (gx > ex[i]) ex[i] = gx;
          if (gy > ey[i]) ey[i] = gy;
        }
      }
    }
    return _EdgeMaps(ex, ey);
  }

  /// Mean edge strength along candidate lines at each position in the band,
  /// keeping the best of the given slopes.
  static _Profile _profile(_EdgeMaps maps, int w, int h, _Band b, List<double> slopes) {
    final e = b.horizontal ? maps.ey : maps.ex;
    final lim = b.horizontal ? h : w;
    final positions = <int>[];
    final scores = <double>[];
    final bestSlopes = <double>[];
    final mid = (b.spanLo + b.spanHi) / 2;
    final spanLim = b.horizontal ? w : h;
    final s0 = math.max(0, b.spanLo.ceil());
    final s1 = math.min(spanLim - 1, b.spanHi.floor());
    final samples = Float64List(((s1 - s0) ~/ 2) + 2);
    for (var p = b.lo; p <= b.hi; p++) {
      var best = 0.0, bestT = 0.0;
      for (final t in slopes) {
        var count = 0;
        for (var s = s0; s <= s1; s += 2) {
          final q = (p + t * (s - mid)).round();
          if (q < 0 || q >= lim) continue;
          samples[count++] = b.horizontal ? e[q * w + s] : e[s * w + q];
        }
        // 35th percentile along the line: high only if the edge runs (most
        // of) the full side, so short streaks on a patterned mat score low.
        final score = count > 0 ? _lowPercentile(samples, count) : 0.0;
        if (score > best) {
          best = score;
          bestT = t;
        }
      }
      positions.add(p);
      scores.add(best);
      bestSlopes.add(bestT);
    }
    return _Profile(positions, scores, bestSlopes);
  }

  /// Significant peaks in a side's profile, outermost first (at most [max]).
  List<_Pick> _significantPeaks(List<double> score, bool outerFirst, {int max = 4}) {
    final n = score.length;
    final out = <_Pick>[];
    if (n < 3) return out;
    for (var k = 0; k < n && out.length < max; k++) {
      final i = outerFirst ? k : n - 1 - k;
      if (i == 0 || i == n - 1) continue;
      if (score[i] < score[i - 1] || score[i] < score[i + 1]) continue; // not a peak
      // Significance is judged against the mat just *outside* the candidate
      // (3..11 px further out). A global floor doesn't work: log space
      // amplifies sensor noise in near-black areas, so a black mat is
      // "noisier" than the card face and would throw up false edges.
      var win = outerFirst
          ? score.sublist(math.max(0, i - 11), math.max(0, i - 2))
          : score.sublist(math.min(n, i + 3), math.min(n, i + 12));
      if (win.length < 4) {
        // Too close to the band's outer end: use the strip just inside
        // instead (on a black-bordered card that's the border itself).
        win = outerFirst
            ? score.sublist(math.min(n, i + 3), math.min(n, i + 10))
            : score.sublist(math.max(0, i - 9), math.max(0, i - 2));
      }
      if (win.isEmpty) continue;
      final base = _median(win);
      final spread = 1.4826 * _median(win.map((v) => (v - base).abs()).toList()) + 1e-6;
      if (score[i] >= base + math.max(6 * spread, minContrast)) {
        out.add(_Pick(i, (score[i] - base) / spread));
      }
    }
    return out;
  }

  /// 35th percentile of the first [count] values (sorts a copy).
  static double _lowPercentile(Float64List values, int count) {
    final v = Float64List.fromList(values.sublist(0, count))..sort();
    return v[((count - 1) * 0.35).round()];
  }

  static double _median(List<double> v) => _percentile(v, 0.5);

  /// Horizontal line y = p1 + t1 (x - m1) meets vertical x = p2 + t2 (y - m2).
  static Pt _intersect(_Line hor, _Line ver) {
    final x = (ver.pos + ver.slope * (hor.pos - hor.slope * hor.mid - ver.mid)) /
        (1 - ver.slope * hor.slope);
    final y = hor.pos + hor.slope * (x - hor.mid);
    return Pt(x, y);
  }

  static double _max(List<double> v) => v.reduce(math.max);

  static double _percentile(List<double> v, double q) {
    final s = List<double>.of(v)..sort();
    final idx = (q * (s.length - 1));
    final lo = idx.floor(), hi = idx.ceil();
    return s[lo] + (s[hi] - s[lo]) * (idx - lo);
  }
}

class RefineResult {
  final Quad quad; // analysis-image pixel coordinates
  final int sidesFound; // 0..4 sides locked onto real edges
  final double angleDegrees;
  RefineResult({required this.quad, required this.sidesFound, required this.angleDegrees});
}

enum _Side { top, bottom, left, right }

class _Band {
  final _Side side;
  final bool horizontal;
  final int lo, hi;
  final double spanLo, spanHi, guidePos;
  _Band(this.side, this.horizontal, this.lo, this.hi, this.spanLo, this.spanHi, this.guidePos);
}

class _Line {
  final double pos, slope, mid;
  _Line(this.pos, this.slope, this.mid);
}

class _Profile {
  final List<int> positions;
  final List<double> scores;
  final List<double> slopes;
  _Profile(this.positions, this.scores, this.slopes);
}

class _Cand {
  final _Line line;

  /// Null for the guide fallback (side not actually seen).
  final double? significance;
  _Cand(this.line, this.significance);
}

class _Pick {
  final int index;
  final double significance;
  _Pick(this.index, this.significance);
}

class _EdgeMaps {
  final Float32List ex, ey;
  _EdgeMaps(this.ex, this.ey);
}
