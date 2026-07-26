import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Built-in chat wallpaper presets (local, no assets/API).
enum ChatWallpaperStyle {
  pattern,
  solid,
  dusk,
  forest,
  sand,
  night;

  static const defaultStyle = ChatWallpaperStyle.pattern;

  String get id => name;

  String get label {
    switch (this) {
      case ChatWallpaperStyle.pattern:
        return 'Узор';
      case ChatWallpaperStyle.solid:
        return 'Однотон';
      case ChatWallpaperStyle.dusk:
        return 'Сумерки';
      case ChatWallpaperStyle.forest:
        return 'Лес';
      case ChatWallpaperStyle.sand:
        return 'Песок';
      case ChatWallpaperStyle.night:
        return 'Ночь';
    }
  }

  static ChatWallpaperStyle fromId(String? raw) {
    for (final style in ChatWallpaperStyle.values) {
      if (style.id == raw) return style;
    }
    return defaultStyle;
  }
}

/// Soft Telegram-like chat wallpaper.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({
    super.key,
    required this.isDark,
    required this.child,
    this.style = ChatWallpaperStyle.defaultStyle,
    this.backgroundImage,
  });

  final bool isDark;
  final Widget child;
  final ChatWallpaperStyle style;
  final ImageProvider? backgroundImage;

  Color get _base {
    switch (style) {
      case ChatWallpaperStyle.pattern:
      case ChatWallpaperStyle.solid:
        return isDark ? const Color(0xFF0E1621) : const Color(0xFFE7EBF0);
      case ChatWallpaperStyle.dusk:
        return isDark ? const Color(0xFF151B2E) : const Color(0xFFD7DEEC);
      case ChatWallpaperStyle.forest:
        return isDark ? const Color(0xFF101A14) : const Color(0xFFD9E6DA);
      case ChatWallpaperStyle.sand:
        return isDark ? const Color(0xFF1C1712) : const Color(0xFFE8DFD2);
      case ChatWallpaperStyle.night:
        return isDark ? const Color(0xFF070B14) : const Color(0xFFC9D0DE);
    }
  }

  Color get _accent {
    switch (style) {
      case ChatWallpaperStyle.pattern:
      case ChatWallpaperStyle.solid:
        return isDark ? const Color(0x14FFFFFF) : const Color(0x14000000);
      case ChatWallpaperStyle.dusk:
        return isDark ? const Color(0x22A8B8FF) : const Color(0x22708AD6);
      case ChatWallpaperStyle.forest:
        return isDark ? const Color(0x2290C8A0) : const Color(0x22609070);
      case ChatWallpaperStyle.sand:
        return isDark ? const Color(0x22D2B48C) : const Color(0x22A08060);
      case ChatWallpaperStyle.night:
        return isDark ? const Color(0x226E8CFF) : const Color(0x224860A0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = backgroundImage;
    if (custom != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _base,
          image: DecorationImage(
            image: custom,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
              BlendMode.darken,
            ),
          ),
        ),
        child: child,
      );
    }

    final showPattern = style != ChatWallpaperStyle.solid;
    return ColoredBox(
      color: _base,
      child: showPattern
          ? CustomPaint(
              painter: _ChatWallpaperPainter(
                patternColor: _accent,
                denser: style == ChatWallpaperStyle.pattern,
              ),
              child: child,
            )
          : child,
    );
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  _ChatWallpaperPainter({
    required this.patternColor,
    this.denser = true,
  });

  final Color patternColor;
  final bool denser;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = patternColor;
    final step = denser ? 28.0 : 36.0;
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
      oldDelegate.patternColor != patternColor ||
      oldDelegate.denser != denser;
}
