import 'dart:math' as math;

import 'package:mtg_dark_scanner/vision/frame.dart';
import 'package:mtg_dark_scanner/vision/geometry.dart';

/// Renders a dark playmat with a black-bordered, black-frame card on it.
/// Mirrors the Python prototype used to tune the refiner.
class SyntheticScene {
  final RgbImage image;
  final Quad truth; // TL, TR, BR, BL in pixels
  final Box guide; // normalised
  SyntheticScene(this.image, this.truth, this.guide);
}

SyntheticScene renderScene({
  int width = 360,
  int height = 640,
  List<int> mat = const [22, 26, 34],
  List<int> border = const [12, 12, 14],
  bool blackBorder = true,
  double dx = 0,
  double dy = 0,
  double angleDeg = 0,
  double scale = 1,
  double noise = 4,
  int seed = 1,
  int streaks = 0,
}) {
  final rnd = math.Random(seed);
  final guide = guideBox(width / height);
  final g = guide.toPixels(width.toDouble(), height.toDouble());
  final cw = g.width * scale, ch = g.height * scale;
  final cx = (g.left + g.right) / 2 + dx, cy = (g.top + g.bottom) / 2 + dy;
  final a = angleDeg * math.pi / 180;
  final ca = math.cos(a), sa = math.sin(a);

  Pt corner(double u, double v) {
    final x = (u - 0.5) * cw, y = (v - 0.5) * ch;
    return Pt(cx + x * ca - y * sa, cy + x * sa + y * ca);
  }

  final truth = Quad([corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1)]);

  // Busy playmat: short thick bright/dark strokes (like flame art) on the mat.
  final strokes = <(double, double, double, double, double, List<int>)>[];
  const palette = [
    [200, 90, 30],
    [250, 160, 60],
    [10, 10, 10],
  ];
  for (var i = 0; i < streaks; i++) {
    final x = rnd.nextDouble() * width, y = rnd.nextDouble() * height;
    final len = 20 + rnd.nextDouble() * 60, ang = rnd.nextDouble() * math.pi;
    final thick = 3 + rnd.nextDouble() * 5;
    strokes.add((x, y, x + len * math.cos(ang), y + len * math.sin(ang), thick, palette[i % 3]));
  }
  List<int>? strokeAt(double px, double py) {
    for (final (x0, y0, x1, y1, t, c) in strokes) {
      final dx = x1 - x0, dy = y1 - y0;
      final l2 = dx * dx + dy * dy;
      var u = ((px - x0) * dx + (py - y0) * dy) / l2;
      u = u < 0 ? 0 : (u > 1 ? 1 : u);
      final ex = x0 + u * dx - px, ey = y0 + u * dy - py;
      if (ex * ex + ey * ey <= t * t / 4) return c;
    }
    return null;
  }
  final img = RgbImage(width, height);
  final b = blackBorder ? border : const [220, 220, 220];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // inverse rotate into card space
      final rx = x + 0.5 - cx, ry = y + 0.5 - cy;
      final u = (rx * ca + ry * sa) / cw + 0.5;
      final v = (-rx * sa + ry * ca) / ch + 0.5;
      List<int> c;
      if (u < 0 || u > 1 || v < 0 || v > 1) {
        c = strokes.isEmpty ? mat : (strokeAt(x + 0.5, y + 0.5) ?? mat);
      } else if (u < 0.045 || u > 0.955 || v < 0.032 || v > 0.968) {
        c = b;
      } else if (v > 0.045 && v < 0.10 && u > 0.065 && u < 0.935) {
        // name bar with a few dark "letters"
        final letter = u > 0.09 && u < 0.7 && ((u * 60).floor() % 3 == 0) && v > 0.06 && v < 0.088;
        c = letter ? const [10, 10, 10] : const [140, 135, 130];
      } else if (v > 0.11 && v < 0.555 && u > 0.075 && u < 0.925) {
        c = const [90, 60, 120];
      } else if (v > 0.635 && v < 0.90 && u > 0.075 && u < 0.925) {
        c = const [205, 200, 190];
      } else {
        c = const [38, 36, 40];
      }
      int n(int v) {
        final r = v + (rnd.nextDouble() * 2 - 1) * noise * 1.7;
        return r < 0 ? 0 : (r > 255 ? 255 : r.round());
      }

      img.setPixel(x, y, n(c[0]), n(c[1]), n(c[2]));
    }
  }
  return SyntheticScene(img, truth, guide);
}

double maxCornerError(Quad a, Quad b) {
  var m = 0.0;
  for (var i = 0; i < 4; i++) {
    final d = math.sqrt(math.pow(a.pts[i].x - b.pts[i].x, 2) + math.pow(a.pts[i].y - b.pts[i].y, 2));
    if (d > m) m = d;
  }
  return m;
}
