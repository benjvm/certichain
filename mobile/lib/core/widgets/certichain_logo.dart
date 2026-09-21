import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class CertiChainLogo extends StatelessWidget {
  const CertiChainLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logotipo de CertiChain',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 56, size.height / 56);
    final outer = _hexagon(const Offset(28, 28), 23);
    canvas.drawPath(
      outer,
      Paint()
        ..color = AppColors.brandPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    final chain = Path()
      ..moveTo(32, 17)
      ..lineTo(39, 22)
      ..lineTo(39, 32)
      ..lineTo(31, 37)
      ..lineTo(24, 33)
      ..lineTo(24, 26)
      ..lineTo(31, 22);
    canvas.drawPath(
      chain,
      Paint()
        ..color = AppColors.brandPrimaryDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      const Offset(24, 33),
      const Offset(17, 38),
      Paint()
        ..color = AppColors.brandPrimary
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _hexagon(Offset center, double radius) {
    final path = Path();
    for (var index = 0; index < 6; index++) {
      final angle = -math.pi / 2 + index * math.pi / 3;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
