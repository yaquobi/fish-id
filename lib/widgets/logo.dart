import 'package:flutter/material.dart';

import '../theme.dart';

/// شعار FISH ID: سمكة داخل زوايا عدسة الكاميرا مع خط مسح ذهبي.
class FishIdMark extends StatelessWidget {
  const FishIdMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final gold = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s
      ..strokeCap = StrokeCap.round;

    // زوايا العدسة.
    const c = 22.0, m = 8.0, e = 92.0;
    for (final (x, y, dx, dy) in [(m, m, 1, 1), (e, m, -1, 1), (m, e, 1, -1), (e, e, -1, -1)]) {
      canvas.drawLine(Offset(x * s, y * s), Offset((x + dx * c) * s, y * s), gold);
      canvas.drawLine(Offset(x * s, y * s), Offset(x * s, (y + dy * c) * s), gold);
    }

    // خط المسح خلف السمكة.
    canvas.drawLine(
      Offset(16 * s, 50 * s),
      Offset(84 * s, 50 * s),
      Paint()
        ..color = AppColors.gold.withValues(alpha: .55)
        ..strokeWidth = 2.4 * s
        ..strokeCap = StrokeCap.round,
    );

    // جسم السمكة (يتجه لليمين) والذيل.
    final body = Path()
      ..moveTo(78 * s, 50 * s)
      ..cubicTo(70 * s, 36 * s, 50 * s, 32 * s, 36 * s, 42 * s)
      ..lineTo(24 * s, 34 * s)
      ..lineTo(27 * s, 50 * s)
      ..lineTo(24 * s, 66 * s)
      ..lineTo(36 * s, 58 * s)
      ..cubicTo(50 * s, 68 * s, 70 * s, 64 * s, 78 * s, 50 * s)
      ..close();
    canvas.drawPath(body, Paint()..color = AppColors.navy);
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6 * s
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(body, white);

    // خط الخياشيم والعين.
    final gill = Path()
      ..moveTo(62 * s, 42 * s)
      ..quadraticBezierTo(58 * s, 50 * s, 62 * s, 58 * s);
    canvas.drawPath(gill, white..strokeWidth = 2.6 * s);
    canvas.drawCircle(Offset(69 * s, 47 * s), 3.2 * s, Paint()..color = AppColors.gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// كلمة FISH ID، وكلمة ID بالذهبي.
class FishIdWordmark extends StatelessWidget {
  const FishIdWordmark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: 'FISH ',
            style: TextStyle(color: Colors.white),
          ),
          const TextSpan(
            text: 'ID',
            style: TextStyle(color: AppColors.gold),
          ),
        ],
      ),
      style: TextStyle(fontFamily: 'ChakraPetch', fontWeight: FontWeight.w700, fontSize: size, letterSpacing: 2),
    ),
  );
}
