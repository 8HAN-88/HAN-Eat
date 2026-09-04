import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_html_reel_video_stub.dart'
    if (dart.library.html) 'web_html_reel_video_html.dart' as impl;

/// Safari PWA: нативный `<video playsinline>` без crossOrigin.
/// Нужен только если Flutter `video_player` не смог открыть файл.
class WebHtmlReelVideo extends StatelessWidget {
  const WebHtmlReelVideo({
    super.key,
    required this.url,
    this.muted = true,
    this.playing = true,
    this.onError,
  });

  final String url;
  final bool muted;
  final bool playing;
  final VoidCallback? onError;

  static bool get isSupported => kIsWeb;

  @override
  Widget build(BuildContext context) {
    return impl.buildWebHtmlReelVideo(
      url: url,
      muted: muted,
      playing: playing,
      onError: onError,
    );
  }
}
