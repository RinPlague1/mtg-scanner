import 'dart:typed_data';

import 'edge_refiner.dart';
import 'frame.dart';
import 'geometry.dart';

/// Result of analysing one camera frame. Plain data so it can cross isolates.
class FrameAnalysis {
  /// Card corners in normalised upright-frame coordinates (for the overlay).
  final Quad quadNorm;
  final int sidesFound;
  final OcrCrop name;
  final OcrCrop setLine;
  final double nameGlare;
  final double cardBrightness; // 0..255 mean luma of the title crop
  final int elapsedMs;

  FrameAnalysis({
    required this.quadNorm,
    required this.sidesFound,
    required this.name,
    required this.setLine,
    required this.nameGlare,
    required this.cardBrightness,
    required this.elapsedMs,
  });

  bool get lockedOnEdges => sidesFound >= 3;
}

/// Enhanced grayscale crop packaged as NV21 (Y = gray, chroma neutral), which
/// is what ML Kit's InputImage.fromBytes accepts on Android.
class OcrCrop {
  final int width;
  final int height;
  final Uint8List nv21;
  OcrCrop(this.width, this.height, this.nv21);
}

/// Pure function run inside a background isolate.
FrameAnalysis analyseFrame(YuvFrame frame, {int analysisWidth = 360}) {
  final sw = Stopwatch()..start();
  final step = (frame.width / analysisWidth).floor().clamp(1, 8).toInt();
  final small = frame.toAnalysisRgb(step);
  final guide = guideBox(frame.width / frame.height);

  final refined = const EdgeRefiner().refine(small, guide);
  // analysis pixel (ax, ay) is sampled around upright pixel ax*step + step/2
  final quadFull = refined.quad.scale(step.toDouble(), step / 2);

  final nameCrop = frame.cropRegion(quadFull, CardRegions.name, 640);
  final setCrop = frame.cropRegion(quadFull, CardRegions.setLine, 720);

  final nameImg = nameCrop.glareFraction > 0.015
      ? _stretch(_flatten(nameCrop.image, 14))
      : _stretch(nameCrop.image);
  final setImg = _stretch(setCrop.image);

  sw.stop();
  return FrameAnalysis(
    quadNorm: quadFull.normalised(frame.width.toDouble(), frame.height.toDouble()),
    sidesFound: refined.sidesFound,
    name: _toNv21(nameImg),
    setLine: _toNv21(setImg),
    nameGlare: nameCrop.glareFraction,
    cardBrightness: nameCrop.meanLuma,
    elapsedMs: sw.elapsedMilliseconds,
  );
}

/// Percentile contrast stretch (2%..98%), then make text dark-on-light, which
/// is what OCR engines are trained on. Black-frame titles are already dark
/// text on a grey bar; the set line is white text on the black border, so it
/// gets inverted.
GrayImage _stretch(GrayImage src) {
  final hist = List<int>.filled(256, 0);
  for (final v in src.data) {
    hist[v]++;
  }
  final n = src.data.length;
  int pct(double q) {
    final target = (q * n).round();
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }

  final lo = pct(0.02), hi = pct(0.98), med = pct(0.5);
  final range = (hi - lo) < 1 ? 1 : (hi - lo);
  final medStretched = ((med - lo) * 255 / range).clamp(0, 255);
  final invert = medStretched < 110;
  final out = GrayImage(src.width, src.height);
  for (var i = 0; i < n; i++) {
    var v = ((src.data[i] - lo) * 255 / range).round();
    if (v < 0) v = 0;
    if (v > 255) v = 255;
    out.data[i] = invert ? 255 - v : v;
  }
  return out;
}

/// Flat-field correction: divide by a local box-blurred background so a glare
/// hotspot over the title becomes the same "paper white" as the rest of the
/// bar, leaving the letters as the only dark thing.
GrayImage _flatten(GrayImage src, int radius) {
  final w = src.width, h = src.height;
  // integral image
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += src.data[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row;
    }
  }
  final out = GrayImage(w, h);
  for (var y = 0; y < h; y++) {
    final y0 = (y - radius).clamp(0, h).toInt(), y1 = (y + radius + 1).clamp(0, h).toInt();
    for (var x = 0; x < w; x++) {
      final x0 = (x - radius).clamp(0, w).toInt(), x1 = (x + radius + 1).clamp(0, w).toInt();
      final area = (x1 - x0) * (y1 - y0);
      final s = integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      final bg = s / area + 1;
      var v = (src.data[y * w + x] / bg * 200).round();
      if (v > 255) v = 255;
      out.data[y * w + x] = v;
    }
  }
  return out;
}

OcrCrop _toNv21(GrayImage g) {
  final w = g.width & ~1, h = g.height & ~1; // NV21 needs even dimensions
  final ySize = w * h;
  final bytes = Uint8List(ySize + ySize ~/ 2);
  for (var y = 0; y < h; y++) {
    bytes.setRange(y * w, y * w + w, g.data, y * g.width);
  }
  bytes.fillRange(ySize, bytes.length, 128);
  return OcrCrop(w, h, bytes);
}
