import 'dart:math';

import 'package:flutter/material.dart';

/// Волна для голосовых: live-уровни при записи или статичный паттерн при воспроизведении.
class ChatVoiceWaveform extends StatelessWidget {
  const ChatVoiceWaveform({
    super.key,
    this.levels,
    this.seed,
    this.progress = 0,
    required this.color,
    this.activeColor,
    this.barCount = 28,
    this.height = 28,
    this.onSeek,
  });

  final List<double>? levels;
  final int? seed;
  final double progress;
  final Color color;
  final Color? activeColor;
  final int barCount;
  final double height;
  /// 0.0–1.0 scrub callback (Telegram-style tap/drag on waveform).
  final ValueChanged<double>? onSeek;

  List<double> _resolveBars() {
    if (levels != null && levels!.isNotEmpty) {
      final src = levels!;
      if (src.length >= barCount) {
        return src.sublist(src.length - barCount);
      }
      final pad = List<double>.filled(barCount - src.length, 0.12);
      return [...pad, ...src];
    }
    final s = seed ?? 1;
    final r = Random(s);
    return List.generate(barCount, (_) => 0.18 + r.nextDouble() * 0.82);
  }

  void _seekAt(Offset local, double width) {
    if (onSeek == null || width <= 0) return;
    onSeek!((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final bars = _resolveBars();
    final played = (progress.clamp(0.0, 1.0) * barCount).floor();
    final highlight = activeColor ?? color;

    final row = SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(bars.length, (i) {
          final h = (height * bars[i]).clamp(4.0, height);
          final active = i < played;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: active ? highlight : color.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );

    if (onSeek == null) return row;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekAt(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _seekAt(d.localPosition, width),
          child: row,
        );
      },
    );
  }
}
