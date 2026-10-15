import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/vision/bmp.dart';

void main() {
  test('24-bit BMP header, padding and bottom-up rows', () {
    // 3x2 image: top row 10,20,30 / bottom row 40,50,60
    final gray = Uint8List.fromList([10, 20, 30, 40, 50, 60]);
    final bmp = grayToBmp(gray, 3, 2);
    final b = ByteData.view(bmp.buffer);
    expect(String.fromCharCodes(bmp.sublist(0, 2)), 'BM');
    const rowSize = 12; // 3 px * 3 bytes = 9, padded to 12
    expect(bmp.length, 54 + rowSize * 2);
    expect(b.getUint32(2, Endian.little), bmp.length);
    expect(b.getUint32(10, Endian.little), 54);
    expect(b.getInt32(18, Endian.little), 3);
    expect(b.getInt32(22, Endian.little), 2);
    expect(b.getUint16(28, Endian.little), 24);
    // First stored row is the bottom image row.
    expect(bmp.sublist(54, 63), [40, 40, 40, 50, 50, 50, 60, 60, 60]);
    expect(bmp.sublist(54 + rowSize, 54 + rowSize + 9), [10, 10, 10, 20, 20, 20, 30, 30, 30]);
  });
}
