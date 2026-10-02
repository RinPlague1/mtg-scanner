import 'dart:typed_data';

import 'geometry.dart';

/// Interleaved 8-bit RGB image used for edge analysis.
class RgbImage {
  final int width;
  final int height;
  final Uint8List data; // length = width * height * 3

  RgbImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height * 3);

  void setPixel(int x, int y, int r, int g, int b) {
    final i = (y * width + x) * 3;
    data[i] = r;
    data[i + 1] = g;
    data[i + 2] = b;
  }
}

/// Single-channel image (OCR input).
class GrayImage {
  final int width;
  final int height;
  final Uint8List data;
  GrayImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height);
}

/// A YUV420 camera frame plus the rotation needed to make it upright.
///
/// Works for the 3-plane YUV_420_888 layout (any pixel / row stride) and for
/// single-buffer NV21 (see [YuvFrame.nv21]). All public sampling methods take
/// *upright portrait* coordinates, so the rest of the pipeline never has to
/// think about sensor orientation.
class YuvFrame {
  final int sensorWidth;
  final int sensorHeight;
  final int rotation; // 0, 90, 180, 270 (clockwise)

  final Uint8List y;
  final int yRowStride;
  final Uint8List u;
  final int uOffset;
  final Uint8List v;
  final int vOffset;
  final int uvRowStride;
  final int uvPixelStride;

  YuvFrame({
    required this.sensorWidth,
    required this.sensorHeight,
    required this.rotation,
    required this.y,
    required this.yRowStride,
    required this.u,
    required this.v,
    required this.uvRowStride,
    required this.uvPixelStride,
    this.uOffset = 0,
    this.vOffset = 0,
  });

  /// NV21: full Y plane followed by interleaved V,U at half resolution.
  factory YuvFrame.nv21(Uint8List bytes, int width, int height, int rotation) {
    final ySize = width * height;
    return YuvFrame(
      sensorWidth: width,
      sensorHeight: height,
      rotation: rotation,
      y: bytes,
      yRowStride: width,
      u: bytes,
      uOffset: ySize + 1,
      v: bytes,
      vOffset: ySize,
      uvRowStride: width,
      uvPixelStride: 2,
    );
  }

  bool get _swap => rotation == 90 || rotation == 270;
  int get width => _swap ? sensorHeight : sensorWidth; // upright width
  int get height => _swap ? sensorWidth : sensorHeight; // upright height

  // Upright (px,py) -> sensor (sx,sy).
  int _sx(int px, int py) {
    switch (rotation) {
      case 90:
        return py;
      case 180:
        return sensorWidth - 1 - px;
      case 270:
        return sensorWidth - 1 - py;
      default:
        return px;
    }
  }

  int _sy(int px, int py) {
    switch (rotation) {
      case 90:
        return sensorHeight - 1 - px;
      case 180:
        return sensorHeight - 1 - py;
      case 270:
        return px;
      default:
        return py;
    }
  }

  int _clampX(int px) => px < 0 ? 0 : (px >= width ? width - 1 : px);
  int _clampY(int py) => py < 0 ? 0 : (py >= height ? height - 1 : py);

  int lumaAt(int px, int py) {
    px = _clampX(px);
    py = _clampY(py);
    return y[_sy(px, py) * yRowStride + _sx(px, py)];
  }

  /// Returns (u, v) chroma at upright pixel, packed as u << 8 | v.
  int chromaAt(int px, int py) {
    px = _clampX(px);
    py = _clampY(py);
    final sx = _sx(px, py) >> 1, sy = _sy(px, py) >> 1;
    final i = sy * uvRowStride + sx * uvPixelStride;
    final ui = uOffset + i, vi = vOffset + i;
    final uu = ui < u.length ? u[ui] : 128;
    final vv = vi < v.length ? v[vi] : 128;
    return (uu << 8) | vv;
  }

  double lumaBilinear(double px, double py) {
    final x0 = px.floor(), y0 = py.floor();
    final fx = px - x0, fy = py - y0;
    final a = lumaAt(x0, y0), b = lumaAt(x0 + 1, y0);
    final c = lumaAt(x0, y0 + 1), d = lumaAt(x0 + 1, y0 + 1);
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy;
  }

  /// Downsampled upright RGB image for edge analysis. Each output pixel is the
  /// 2x2 luma average at the centre of its step x step block (cheap denoise),
  /// chroma is nearest-neighbour.
  RgbImage toAnalysisRgb(int step) {
    final ow = width ~/ step, oh = height ~/ step;
    final out = RgbImage(ow, oh);
    final half = step ~/ 2;
    for (var ay = 0; ay < oh; ay++) {
      final py = ay * step + half;
      for (var ax = 0; ax < ow; ax++) {
        final px = ax * step + half;
        final yy = (lumaAt(px, py) + lumaAt(px + 1, py) + lumaAt(px, py + 1) + lumaAt(px + 1, py + 1)) >> 2;
        final uv = chromaAt(px, py);
        final cu = (uv >> 8) - 128, cv = (uv & 0xff) - 128;
        out.setPixel(
          ax,
          ay,
          _clamp255(yy + 1.402 * cv),
          _clamp255(yy - 0.344 * cu - 0.714 * cv),
          _clamp255(yy + 1.772 * cu),
        );
      }
    }
    return out;
  }

  /// Warp a card-space region to a grayscale crop. Also reports how much of
  /// the crop is specular glare (very bright and colourless) and its mean
  /// brightness, which drive the on-screen hints.
  CropResult cropRegion(Quad quad, Box region, int outWidth) {
    final regionAspect = (region.width * kCardAspect) / region.height; // physical w/h
    var outHeight = (outWidth / regionAspect).round();
    if (outHeight < 8) outHeight = 8;
    final img = GrayImage(outWidth, outHeight);
    var glare = 0;
    var sum = 0.0;
    for (var j = 0; j < outHeight; j++) {
      final vv = region.top + region.height * (j + 0.5) / outHeight;
      for (var i = 0; i < outWidth; i++) {
        final uu = region.left + region.width * (i + 0.5) / outWidth;
        final p = quad.map(uu, vv);
        final l = lumaBilinear(p.x, p.y);
        final li = _clamp255(l);
        img.data[j * outWidth + i] = li;
        sum += l;
        if (li > 235) {
          final uv = chromaAt(p.x.round(), p.y.round());
          final sat = ((uv >> 8) - 128).abs() + ((uv & 0xff) - 128).abs();
          if (sat < 20) glare++;
        }
      }
    }
    final n = outWidth * outHeight;
    return CropResult(img, glare / n, sum / n);
  }
}

class CropResult {
  final GrayImage image;
  final double glareFraction;
  final double meanLuma;
  CropResult(this.image, this.glareFraction, this.meanLuma);
}

int _clamp255(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
