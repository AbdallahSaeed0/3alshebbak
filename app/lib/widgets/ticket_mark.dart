import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// The عالشباك mark: a gold ticket stamped with «ع», stub and tear line on the
/// left, an amber ticket tucked behind. Drawn on a 120×120 grid (same geometry
/// as the design canvas's Mark component).
///
/// [glow] 0..1 per stub dot drives the splash's chasing-lights animation.
class TicketMark extends StatelessWidget {
  const TicketMark({super.key, this.size = 120, this.glow});

  final double size;
  final List<double>? glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TicketPainter(glow: glow ?? const [1, 1, 1]),
      ),
    );
  }
}

class _TicketPainter extends CustomPainter {
  _TicketPainter({required this.glow});

  final List<double> glow;

  /// Rounded ticket with semicircle notches top and bottom at the tear line (x=40).
  static Path _ticket() => Path()
    ..moveTo(22, 30)
    ..lineTo(34, 30)
    ..arcToPoint(
      const Offset(46, 30),
      radius: const Radius.circular(6),
      clockwise: false,
    )
    ..lineTo(98, 30)
    ..arcToPoint(const Offset(106, 38), radius: const Radius.circular(8))
    ..lineTo(106, 82)
    ..arcToPoint(const Offset(98, 90), radius: const Radius.circular(8))
    ..lineTo(46, 90)
    ..arcToPoint(
      const Offset(34, 90),
      radius: const Radius.circular(6),
      clockwise: false,
    )
    ..lineTo(22, 90)
    ..arcToPoint(const Offset(14, 82), radius: const Radius.circular(8))
    ..lineTo(14, 38)
    ..arcToPoint(const Offset(22, 30), radius: const Radius.circular(8))
    ..close();

  void _rotateAround(Canvas canvas, double degrees) {
    canvas
      ..translate(60, 60)
      ..rotate(degrees * math.pi / 180)
      ..translate(-60, -60);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 120);
    final ticket = _ticket();

    // The ticket behind.
    canvas.save();
    _rotateAround(canvas, 6);
    canvas.translate(4, -3);
    canvas.drawPath(ticket, Paint()..color = AppColors.amber);
    canvas.restore();

    // The front ticket.
    canvas.save();
    _rotateAround(canvas, -10);
    canvas.drawPath(ticket, Paint()..color = AppColors.gold);

    final ink = Paint()
      ..color = AppColors.onGold
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = 38.0; y < 82; y += 6) {
      canvas.drawLine(Offset(40, y), Offset(40, math.min(y + 3, 82)), ink);
    }
    for (var i = 0; i < 3; i++) {
      final g = glow[i % glow.length].clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(27, 46.0 + i * 14),
        3.2,
        Paint()..color = AppColors.onGold.withValues(alpha: 0.35 + 0.65 * g),
      );
    }

    final letter = TextPainter(
      text: TextSpan(
        text: 'ع',
        style: GoogleFonts.lalezar(
          fontSize: 50,
          color: AppColors.onGold,
          height: 1,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    letter.paint(canvas, Offset(73 - letter.width / 2, 58 - letter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TicketPainter old) => !_sameGlow(old.glow, glow);
}

bool _sameGlow(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
