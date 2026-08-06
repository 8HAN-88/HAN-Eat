import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fullscreen particle overlay for Telegram-like message send effects.
class MessageEffectOverlay extends StatefulWidget {
  const MessageEffectOverlay({
    super.key,
    required this.effectId,
    this.duration = const Duration(milliseconds: 1800),
    this.onCompleted,
  });

  final String effectId;
  final Duration duration;
  final VoidCallback? onCompleted;

  @override
  State<MessageEffectOverlay> createState() => _MessageEffectOverlayState();
}

class _MessageEffectOverlayState extends State<MessageEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _particles = _spawnParticles(widget.effectId);
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _EffectPainter(
              progress: _controller.value,
              particles: _particles,
              effectId: widget.effectId,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.spin,
    required this.kind,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double spin;
  final int kind;
}

List<_Particle> _spawnParticles(String effectId) {
  final rng = math.Random(effectId.hashCode ^ 42);
  final colors = _colorsFor(effectId);
  final count = switch (effectId) {
    'hearts' => 36,
    'thumbs_up' => 28,
    'fireworks' => 55,
    'celebration' => 48,
    _ => 60, // confetti
  };
  return List.generate(count, (i) {
    final angle = rng.nextDouble() * math.pi * 2;
    final speed = 0.25 + rng.nextDouble() * 0.85;
    return _Particle(
      x: 0.35 + rng.nextDouble() * 0.3,
      y: effectId == 'confetti' || effectId == 'celebration'
          ? -0.05 + rng.nextDouble() * 0.15
          : 0.45 + rng.nextDouble() * 0.15,
      vx: math.cos(angle) * speed * (effectId == 'fireworks' ? 1.2 : 0.55),
      vy: effectId == 'confetti' || effectId == 'celebration'
          ? 0.35 + rng.nextDouble() * 0.7
          : math.sin(angle) * speed,
      size: 4 + rng.nextDouble() * 8,
      color: colors[rng.nextInt(colors.length)],
      spin: (rng.nextDouble() - 0.5) * 8,
      kind: rng.nextInt(3),
    );
  });
}

List<Color> _colorsFor(String effectId) {
  switch (effectId) {
    case 'hearts':
      return const [
        Color(0xFFE53935),
        Color(0xFFEC407A),
        Color(0xFFF48FB1),
        Color(0xFFFFCDD2),
      ];
    case 'thumbs_up':
      return const [
        Color(0xFF42A5F5),
        Color(0xFF1E88E5),
        Color(0xFF90CAF9),
        Color(0xFFFFC107),
      ];
    case 'fireworks':
      return const [
        Color(0xFFFFEB3B),
        Color(0xFFFF5722),
        Color(0xFFE040FB),
        Color(0xFF00E5FF),
        Color(0xFFFFFFFF),
      ];
    case 'celebration':
      return const [
        Color(0xFFFFD54F),
        Color(0xFF66BB6A),
        Color(0xFF42A5F5),
        Color(0xFFEF5350),
        Color(0xFFAB47BC),
      ];
    default:
      return const [
        Color(0xFFFF5252),
        Color(0xFFFFEB3B),
        Color(0xFF69F0AE),
        Color(0xFF40C4FF),
        Color(0xFFFF80AB),
        Color(0xFFFFFFFF),
      ];
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter({
    required this.progress,
    required this.particles,
    required this.effectId,
  });

  final double progress;
  final List<_Particle> particles;
  final String effectId;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);
    for (final p in particles) {
      final t = progress;
      final gravity = effectId == 'confetti' || effectId == 'celebration'
          ? 0.9 * t * t
          : 0.15 * t * t;
      final x = (p.x + p.vx * t) * size.width;
      final y = (p.y + p.vy * t + gravity) * size.height;
      final paint = Paint()
        ..color = p.color.withValues(alpha: fade.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      final rotation = p.spin * t;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      if (effectId == 'hearts') {
        _drawHeart(canvas, paint, p.size);
      } else if (p.kind == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else if (p.kind == 1) {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      } else {
        final path = Path()
          ..moveTo(0, -p.size * 0.5)
          ..lineTo(p.size * 0.4, p.size * 0.4)
          ..lineTo(-p.size * 0.4, p.size * 0.4)
          ..close();
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  void _drawHeart(Canvas canvas, Paint paint, double size) {
    final s = size * 0.55;
    final path = Path()
      ..moveTo(0, s * 0.35)
      ..cubicTo(-s, -s * 0.2, -s * 0.5, -s, 0, -s * 0.45)
      ..cubicTo(s * 0.5, -s, s, -s * 0.2, 0, s * 0.35);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EffectPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
