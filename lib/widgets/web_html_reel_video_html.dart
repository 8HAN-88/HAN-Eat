import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildWebHtmlReelVideo({
  required String url,
  required bool muted,
  required bool playing,
  VoidCallback? onError,
}) {
  return _HtmlReelVideo(
    url: url,
    muted: muted,
    playing: playing,
    onError: onError,
  );
}

class _HtmlReelVideo extends StatefulWidget {
  const _HtmlReelVideo({
    required this.url,
    required this.muted,
    required this.playing,
    this.onError,
  });

  final String url;
  final bool muted;
  final bool playing;
  final VoidCallback? onError;

  @override
  State<_HtmlReelVideo> createState() => _HtmlReelVideoState();
}

class _HtmlReelVideoState extends State<_HtmlReelVideo> {
  late final String _viewType;
  html.VideoElement? _video;

  @override
  void initState() {
    super.initState();
    _viewType = 'hanwe-html-reel-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final video = html.VideoElement()
        ..src = widget.url
        ..muted = widget.muted
        ..autoplay = widget.playing
        ..loop = true
        ..preload = 'auto'
        ..controls = false
        ..style.border = 'none'
        ..style.objectFit = 'cover'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#000';
      video.setAttribute('playsinline', 'true');
      video.setAttribute('webkit-playsinline', 'true');
      if (widget.muted) {
        video.setAttribute('muted', 'true');
      }
      video.onError.listen((_) {
        widget.onError?.call();
      });
      _video = video;
      if (widget.playing) {
        video.play().catchError((_) {});
      }
      return video;
    });
  }

  @override
  void didUpdateWidget(covariant _HtmlReelVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final video = _video;
    if (video == null) return;
    if (oldWidget.url != widget.url) {
      video.src = widget.url;
      video.load();
    }
    video.muted = widget.muted;
    if (widget.playing) {
      video.play().catchError((_) {});
    } else {
      video.pause();
    }
  }

  @override
  void dispose() {
    final video = _video;
    _video = null;
    if (video != null) {
      video.pause();
      video.src = '';
      video.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
