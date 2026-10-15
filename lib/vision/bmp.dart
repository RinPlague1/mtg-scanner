import 'dart:typed_data';

/// Encodes an 8-bit grayscale image (row-major, [width] × [height]) as a
/// 24-bit BMP. Used to hand OCR crops to ML Kit as a file on phones where its
/// raw-bytes input fails (InputImageConverterError). BMP needs no compression
/// library and Android's BitmapFactory reads it natively.
Uint8List grayToBmp(Uint8List gray, int width, int height) {
  final rowSize = (width * 3 + 3) & ~3; // rows padded to 4 bytes
  final pixelBytes = rowSize * height;
  final fileSize = 54 + pixelBytes;
  final out = Uint8List(fileSize);
  final b = ByteData.view(out.buffer);

  // BITMAPFILEHEADER
  out[0] = 0x42; // 'B'
  out[1] = 0x4D; // 'M'
  b.setUint32(2, fileSize, Endian.little);
  b.setUint32(10, 54, Endian.little); // pixel data offset

  // BITMAPINFOHEADER
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, width, Endian.little);
  b.setInt32(22, height, Endian.little); // positive = bottom-up rows
  b.setUint16(26, 1, Endian.little); // planes
  b.setUint16(28, 24, Endian.little); // bits per pixel
  b.setUint32(34, pixelBytes, Endian.little);
  b.setInt32(38, 2835, Endian.little); // 72 dpi
  b.setInt32(42, 2835, Endian.little);

  for (var y = 0; y < height; y++) {
    final src = (height - 1 - y) * width; // bottom-up
    var dst = 54 + y * rowSize;
    for (var x = 0; x < width; x++) {
      final v = gray[src + x];
      out[dst++] = v;
      out[dst++] = v;
      out[dst++] = v;
    }
  }
  return out;
}
