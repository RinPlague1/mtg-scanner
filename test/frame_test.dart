import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/vision/frame.dart';

void main() {
  // 4x2 sensor image (landscape) with luma = index
  YuvFrame make(int rotation) {
    final y = Uint8List.fromList(List.generate(8, (i) => i * 10));
    final uv = Uint8List.fromList(List.filled(4, 128));
    return YuvFrame(
      sensorWidth: 4,
      sensorHeight: 2,
      rotation: rotation,
      y: y,
      yRowStride: 4,
      u: uv,
      v: uv,
      uvRowStride: 2,
      uvPixelStride: 1,
    );
  }

  test('rotation 90 makes the frame portrait and rotates clockwise', () {
    final f = make(90);
    expect(f.width, 2);
    expect(f.height, 4);
    // Upright top-left is the sensor's bottom-left.
    expect(f.lumaAt(0, 0), 40); // sensor (0,1)
    expect(f.lumaAt(1, 0), 0); // sensor (0,0)
    expect(f.lumaAt(1, 3), 30); // sensor (3,0)
  });

  test('rotation 270', () {
    final f = make(270);
    expect(f.lumaAt(0, 0), 30); // sensor (3,0)
    expect(f.lumaAt(1, 3), 40); // sensor (0,1)
  });

  test('nv21 chroma offsets', () {
    final bytes = Uint8List(4 * 2 + 4)..setAll(8, [200, 50, 200, 50]); // V,U interleaved
    final f = YuvFrame.nv21(bytes, 4, 2, 0);
    final uv = f.chromaAt(0, 0);
    expect(uv >> 8, 50); // U
    expect(uv & 0xff, 200); // V
  });
}
