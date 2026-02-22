import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';

class DottedBackground extends StatelessWidget {
  const DottedBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotsPainter(
        dotColor: AppColors.ink.withValues(alpha: 0.05),
        spacing: 18,
        radius: 1.2,
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.dotColor,
    required this.spacing,
    required this.radius,
  });

  final Color dotColor;
  final double spacing;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.spacing != spacing ||
        oldDelegate.radius != radius;
  }
}
