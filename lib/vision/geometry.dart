import 'dart:math' as math;

/// Physical card size is 63 x 88 mm.
const double kCardAspect = 63.0 / 88.0; // width / height

class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);

  Pt scale(double s, [double offset = 0]) => Pt(x * s + offset, y * s + offset);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Axis-aligned rectangle in normalised [0..1] or pixel coordinates.
class Box {
  final double left, top, right, bottom;
  const Box(this.left, this.top, this.right, this.bottom);
  double get width => right - left;
  double get height => bottom - top;

  Box toPixels(double w, double h) =>
      Box(left * w, top * h, right * w, bottom * h);
}

/// Card corners, always ordered TL, TR, BR, BL (in image coordinates).
class Quad {
  final List<Pt> pts;
  const Quad(this.pts) : assert(pts.length == 4);

  factory Quad.fromBox(Box b) => Quad([
        Pt(b.left, b.top),
        Pt(b.right, b.top),
        Pt(b.right, b.bottom),
        Pt(b.left, b.bottom),
      ]);

  Quad scale(double s, [double offset = 0]) =>
      Quad(pts.map((p) => p.scale(s, offset)).toList());

  Quad normalised(double w, double h) =>
      Quad(pts.map((p) => Pt(p.x / w, p.y / h)).toList());

  /// Map card-space (u,v) in [0..1] to image space with bilinear corner
  /// interpolation. Accurate enough for the mild perspective of a hand-held
  /// phone held roughly parallel to the card.
  Pt map(double u, double v) {
    final a = pts[0], b = pts[1], c = pts[2], d = pts[3];
    final w0 = (1 - u) * (1 - v), w1 = u * (1 - v), w2 = u * v, w3 = (1 - u) * v;
    return Pt(a.x * w0 + b.x * w1 + c.x * w2 + d.x * w3,
        a.y * w0 + b.y * w1 + c.y * w2 + d.y * w3);
  }

  double get topWidth => _dist(pts[0], pts[1]);
  double get bottomWidth => _dist(pts[3], pts[2]);
  double get leftHeight => _dist(pts[0], pts[3]);
  double get rightHeight => _dist(pts[1], pts[2]);

  static double _dist(Pt a, Pt b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
}

/// The on-screen guide the user lines the card up with, in normalised
/// coordinates of a portrait frame with the given width/height ratio.
/// Shared by the overlay painter and the analysis isolate so they always agree.
Box guideBox(double frameAspectWH, {double widthFraction = 0.78, double centreY = 0.46}) {
  final w = widthFraction;
  // pixel height = w*W / kCardAspect; normalised = that / H
  var h = w / kCardAspect * frameAspectWH;
  var ww = w;
  if (h > 0.9) {
    // very wide frames: constrain by height instead
    ww = w * 0.9 / h;
    h = 0.9;
  }
  final left = (1 - ww) / 2;
  var top = centreY - h / 2;
  if (top < 0.02) top = 0.02;
  return Box(left, top, left + ww, top + h);
}

/// Regions of interest in card space (u: 0..1 across, v: 0..1 down).
///
/// They are deliberately padded beyond the printed elements. When a black
/// border sits on a black mat and is literally invisible, the refiner may lock
/// onto the inner edge of the border (about 4.5% inside the true edge). The
/// padding means the title and the collector line are still fully inside the
/// crop under either hypothesis — the set line in particular is printed *on*
/// the black border, so the set crop extends past the card's bottom edge.
class CardRegions {
  /// Title bar, excluding the mana cost on the right.
  static const name = Box(0.035, 0.010, 0.80, 0.125);

  /// Collector number / set code / language (bottom-left, M15 frame and later).
  static const setLine = Box(-0.03, 0.895, 0.52, 1.04);
}
