import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/reels/application/dom_video_touch_policy.dart';
import 'web_dom_video_layer_stub.dart'
    if (dart.library.html) 'web_dom_video_layer_html.dart' as impl;

/// Safari / iOS: ролик только картинка под UI, как в Instagram.
/// Жесты (лайк, свайп, табы) всегда у Flutter, не у `<video>`.
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
    this.immersive = false,
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

  /// Полноэкранные Reels. Карточки ленты остаются `false`, чтобы при
  /// старте не вырезать canvas и не клеить `<video>` на весь экран.
  final bool immersive;
  final VoidCallback? onFailed;

  static bool get isSupported => kIsWeb;

  /// iPhone / iPad / desktop Safari — CanvasKit не пробивает platform view.
  static bool get isPreferred => impl.isDomReelVideoPreferred;

  /// Снять застрявший полноэкранный щит, который глушит все тапы в PWA.
  static void releaseStuckTouchShield() => impl.forceReleaseDomVideoTouchShield();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = MediaQuery.sizeOf(context);
        final allowed = active &&
            DomVideoTouchPolicy.allowDomVideoAttach(
              uiReady: DomVideoTouchPolicy.uiInteractive,
              videoWidth: constraints.maxWidth,
              videoHeight: constraints.maxHeight,
              viewWidth: view.width,
              viewHeight: view.height,
              fullscreenSurface: immersive,
            );
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (behindCanvas && allowed) const CanvasPunchHole(),
              impl.buildWebDomVideoLayer(
                urls: urls,
                active: active,
                playing: playing,
                muted: muted,
                behindCanvas: behindCanvas,
                fit: fit,
                borderRadius: borderRadius,
                revealInsets: revealInsets,
                immersive: immersive,
                onFailed: onFailed,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Вырезает непрозрачные пиксели CanvasKit, чтобы был виден DOM под flutter-view.
class CanvasPunchHole extends StatelessWidget {
  const CanvasPunchHole({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        painter: _PunchHolePainter(),
        size: Size.infinite,
      ),
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
