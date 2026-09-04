import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_dom_video_layer_stub.dart'
    if (dart.library.html) 'web_dom_video_layer_html.dart' as impl;

/// Safari / iOS WebKit: `<video>` уходит в нативный слой и жрёт тапы.
/// Ролик рисуем под canvas, поверх — прозрачный щит, который отдаёт
/// жесты во Flutter (лайк, свайп, табы).
class WebDomVideoLayer extends StatelessWidget {
  const WebDomVideoLayer({
    super.key,
    required this.urls,
    this.active = true,
    this.playing = true,
    this.muted = true,
    this.behindCanvas = true,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.revealInsets = EdgeInsets.zero,
    this.onFailed,
  });

  final List<String> urls;
  final bool active;
  final bool playing;
  final bool muted;
  final bool behindCanvas;
  final BoxFit fit;
  final double borderRadius;
  final EdgeInsets revealInsets;
  final VoidCallback? onFailed;

  static bool get isSupported => kIsWeb;

  /// iPhone / iPad / desktop Safari — CanvasKit не пробивает platform view.
  static bool get isPreferred => impl.isDomReelVideoPreferred;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (behindCanvas && active) const CanvasPunchHole(),
        impl.buildWebDomVideoLayer(
          urls: urls,
          active: active,
          playing: playing,
          muted: muted,
          behindCanvas: behindCanvas,
          fit: fit,
          borderRadius: borderRadius,
          revealInsets: revealInsets,
          onFailed: onFailed,
        ),
      ],
    );
  }
}

/// Вырезает непрозрачные пиксели CanvasKit, чтобы был виден DOM под flutter-view.
class CanvasPunchHole extends StatelessWidget {
  const CanvasPunchHole({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _PunchHolePainter(),
      size: Size.infinite,
    );
  }
}

class _PunchHolePainter extends CustomPainter {
  const _PunchHolePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.clear,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
