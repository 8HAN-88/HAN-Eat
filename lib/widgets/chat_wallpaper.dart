import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft Telegram-like chat wallpaper pattern.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({
    super.key,
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF0E1621) : const Color(0xFFE7EBF0);
    return ColoredBox(
      color: base,
      child: CustomPaint(
        painter: _ChatWallpaperPainter(isDark: isDark),
        child: child,
      ),
    );
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  _ChatWallpaperPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0x14FFFFFF)
          : const Color(0x14000000);
    const step = 28.0;
    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * step + (r.isOdd ? step * 0.5 : 0);
        final y = r * step;
        final seed = (r * 31 + c * 17) % 7;
        if (seed == 0) {
          canvas.drawCircle(Offset(x, y), 1.6, paint);
        } else if (seed == 2) {
          canvas.drawRect(
            Rect.fromCenter(center: Offset(x, y), width: 3.2, height: 3.2),
            paint,
          );
        } else if (seed == 4) {
          final path = Path()
            ..moveTo(x, y - 2.2)
            ..lineTo(x + 2.0, y + 1.6)
            ..lineTo(x - 2.0, y + 1.6)
            ..close();
          canvas.drawPath(path, paint);
        } else if (seed == 5) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(x, y), radius: 2.4),
            -math.pi * 0.2,
            math.pi * 1.2,
            false,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.1,
          );
          paint.style = PaintingStyle.fill;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
