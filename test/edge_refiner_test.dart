import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/vision/edge_refiner.dart';
import 'package:mtg_dark_scanner/vision/geometry.dart';

import 'synthetic.dart';

void main() {
  const refiner = EdgeRefiner();

  void expectLocked(SyntheticScene s, {double tol = 3.5, int minSides = 4}) {
    final r = refiner.refine(s.image, s.guide);
    final err = maxCornerError(r.quad, s.truth);
    expect(r.sidesFound, greaterThanOrEqualTo(minSides), reason: 'sides found');
    expect(err, lessThan(tol), reason: 'corner error ${err.toStringAsFixed(1)}px, quad ${r.quad.pts}');
  }

  test('black border on dark mat, aligned', () => expectLocked(renderScene()));

  test('black border, shifted and rotated', () {
    expectLocked(renderScene(dx: 13, dy: -20, angleDeg: 3, scale: 0.95));
  });

  test('black border, large offset the other way', () {
    expectLocked(renderScene(dx: -23, dy: 26, angleDeg: -4, scale: 1.03));
  });

  test('noisy low-light sensor', () {
    expectLocked(renderScene(dx: -8, dy: 13, angleDeg: -2, noise: 10), tol: 4.5);
  });

  test('white border still works', () {
    expectLocked(renderScene(blackBorder: false, dx: 10, dy: 10, angleDeg: 2));
  });

  test('busy patterned mat (flame-like strokes) around the card', () {
    for (final seed in [1, 2, 3, 4]) {
      expectLocked(renderScene(streaks: 40, seed: seed, dx: 8, dy: 10, angleDeg: -2, scale: 0.93), tol: 5);
    }
  });

  test('smaller card on a busy mat', () {
    for (final seed in [5, 6, 7]) {
      expectLocked(renderScene(streaks: 40, seed: seed, dx: -6, dy: 4, angleDeg: 3, scale: 0.86), tol: 5);
    }
  });

  test('border identical to mat falls back to an inner edge, inside crop padding', () {
    final s = renderScene(mat: const [12, 12, 14], dx: 10, dy: 10, angleDeg: 2);
    final r = refiner.refine(s.image, s.guide);
    // Within ~5% of card width: the padded title / set crops still cover it.
    final cardW = s.truth.topWidth;
    expect(maxCornerError(r.quad, s.truth), lessThan(0.08 * cardW));
  });

  test('empty mat returns the guide', () {
    final s = renderScene(scale: 0.0001);
    final r = refiner.refine(s.image, s.guide);
    final g = Quad.fromBox(s.guide.toPixels(s.image.width.toDouble(), s.image.height.toDouble()));
    expect(maxCornerError(r.quad, g), lessThan(30));
  });
}
