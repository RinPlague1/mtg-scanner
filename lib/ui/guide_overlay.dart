import 'package:flutter/material.dart';

import '../vision/geometry.dart';

/// Draws the card-shaped guide, dims everything outside it, and outlines the
/// edges the refiner actually found (green = locked on, amber = partly
/// guessed from the guide).
class GuideOverlay extends CustomPainter {
  final Quad? quad;
  final int sidesFound;
  GuideOverlay({required this.quad, required this.sidesFound});

  @override
  void paint(Canvas canvas, Size size) {
    final g = guideBox(size.width / size.height);
    final rect = Rect.fromLTRB(
      g.left * size.width,
      g.top * size.height,
      g.right * size.width,
      g.bottom * size.height,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.045));

    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rr);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.7),
    );

    // Title / collector line hints so users know what must be visible.
    final hint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.25);
    Rect sub(Box r) => Rect.fromLTRB(
          rect.left + r.left.clamp(0.0, 1.0) * rect.width,
          rect.top + r.top.clamp(0.0, 1.0) * rect.height,
          rect.left + r.right.clamp(0.0, 1.0) * rect.width,
          rect.top + r.bottom.clamp(0.0, 1.0) * rect.height,
        );
    canvas.drawRect(sub(CardRegions.name), hint);
    canvas.drawRect(sub(CardRegions.setLine), hint);

    final q = quad;
    if (q != null && sidesFound > 0) {
      final p = Path()
        ..moveTo(q.pts[0].x * size.width, q.pts[0].y * size.height);
      for (var i = 1; i < 4; i++) {
        p.lineTo(q.pts[i].x * size.width, q.pts[i].y * size.height);
      }
      p.close();
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = sidesFound >= 3 ? Colors.greenAccent : Colors.amberAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GuideOverlay old) => old.quad != quad || old.sidesFound != sidesFound;
}
