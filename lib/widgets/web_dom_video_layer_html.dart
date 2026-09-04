import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

bool get isDomReelVideoPreferred {
  try {
    final ua = html.window.navigator.userAgent;
    final lower = ua.toLowerCase();
    final ios = lower.contains('iphone') ||
        lower.contains('ipad') ||
        lower.contains('ipod') ||
        (lower.contains('mac') &&
            (html.window.navigator.maxTouchPoints ?? 0) > 1);
    if (ios) return true;
    final safari = lower.contains('safari') &&
        !lower.contains('chrome') &&
        !lower.contains('crios') &&
        !lower.contains('fxios') &&
        !lower.contains('edg');
    return safari;
  } catch (_) {
    return false;
  }
}

Widget buildWebDomVideoLayer({
  required List<String> urls,
  required bool active,
  required bool playing,
  required bool muted,
  required bool behindCanvas,
  required BoxFit fit,
  required double borderRadius,
  required EdgeInsets revealInsets,
  VoidCallback? onFailed,
}) {
  return _DomReelHost(
    urls: urls,
    active: active,
    playing: playing,
    muted: muted,
    behindCanvas: true,
    fit: fit,
    borderRadius: borderRadius,
    revealInsets: EdgeInsets.zero,
    onFailed: onFailed,
  );
}

final Map<String, html.VideoElement> _videos = {};

html.Element? _flutterHost() =>
    html.document.querySelector('flutter-view') ??
    html.document.querySelector('flt-glass-pane');

void _ensureFlutterAboveVideo() {
  final flutter = _flutterHost();
  if (flutter != null) {
    flutter.style
      ..setProperty('position', 'relative')
      ..setProperty('z-index', '2')
      ..setProperty('isolation', 'isolate')
      ..setProperty('transform', 'translateZ(0)')
      ..setProperty('pointer-events', 'auto')
      ..setProperty('background-color', 'transparent');
  }
  for (final canvas in html.document.querySelectorAll('canvas')) {
    canvas.style.setProperty('background-color', 'transparent');
  }
}

void _reapOrphans() {
  final live = _videos.values.toSet();
  for (final node in html.document.querySelectorAll('video.hanwe-dom-reel')) {
    if (node is html.VideoElement && !live.contains(node)) {
      node.pause();
      node.src = '';
      node.remove();
    }
  }
}

html.VideoElement _createVideo({required String id}) {
  _reapOrphans();
  final video = html.VideoElement()
    ..autoplay = false
    ..loop = true
    ..controls = false
    ..preload = 'auto'
    ..className = 'hanwe-dom-reel';
  video.setAttribute('playsinline', 'true');
  video.setAttribute('webkit-playsinline', 'true');
  video.setAttribute('disablepictureinpicture', 'true');
  video.setAttribute('controlslist', 'nodownload nofullscreen noremoteplayback');
  video.setAttribute('data-hanwe-dom-reel', id);
  video.style
    ..setProperty('position', 'fixed')
    ..setProperty('left', '0')
    ..setProperty('top', '0')
    ..setProperty('width', '0')
    ..setProperty('height', '0')
    ..setProperty('object-fit', 'cover')
    ..setProperty('z-index', '0')
    ..setProperty('pointer-events', 'none')
    ..setProperty('touch-action', 'none')
    ..setProperty('background', '#000')
    ..setProperty('opacity', '0')
    ..setProperty('margin', '0')
    ..setProperty('padding', '0')
    ..setProperty('border', 'none')
    ..setProperty('clip-path', 'none');

  final flutter = _flutterHost();
  if (flutter != null && flutter.parentNode != null) {
    flutter.parentNode!.insertBefore(video, flutter);
  } else {
    final body = html.document.body;
    if (body != null && body.firstChild != null) {
      body.insertBefore(video, body.firstChild);
    } else {
      body?.append(video);
    }
  }
  return video;
}

class _DomReelHost extends StatefulWidget {
  const _DomReelHost({
    required this.urls,
    required this.active,
    required this.playing,
    required this.muted,
    required this.behindCanvas,
    required this.fit,
    required this.borderRadius,
    required this.revealInsets,
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

  @override
  State<_DomReelHost> createState() => _DomReelHostState();
}

class _DomReelHostState extends State<_DomReelHost> {
  late final String _id;
  int _urlIndex = 0;
  bool _failed = false;
  bool _frameArmed = false;
  StreamSubscription<html.Event>? _errorSub;
  StreamSubscription<html.Event>? _canPlaySub;

  @override
  void initState() {
    super.initState();
    _id = 'hanwe-dom-${identityHashCode(this)}';
    _ensureFlutterAboveVideo();
    _armFrame();
  }

  @override
  void didUpdateWidget(covariant _DomReelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.urls, widget.urls)) {
      _urlIndex = 0;
      _failed = false;
      _videos[_id]?.src = '';
    }
    _sync(forceSrc: !_listEquals(oldWidget.urls, widget.urls));
  }

  @override
  void dispose() {
    _frameArmed = false;
    _errorSub?.cancel();
    _canPlaySub?.cancel();
    final video = _videos.remove(_id);
    if (video != null) {
      video.pause();
      video.src = '';
      video.remove();
    }
    _reapOrphans();
    super.dispose();
  }

  void _armFrame() {
    if (_frameArmed) return;
    _frameArmed = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (!mounted) {
      _frameArmed = false;
      return;
    }
    _sync();
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _sync({bool forceSrc = false}) {
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!widget.active || !routeCurrent || widget.urls.isEmpty || _failed) {
      _hide();
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _hide();
      return;
    }
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    if (size.width < 2 || size.height < 2) {
      _hide();
      return;
    }

    final viewW = html.window.innerWidth ?? 0;
    final viewH = html.window.innerHeight ?? 0;
    final offscreen = offset.dx + size.width < 0 ||
        offset.dy + size.height < 0 ||
        offset.dx > viewW ||
        offset.dy > viewH;
    if (offscreen) {
      _hide();
      return;
    }

    _ensureFlutterAboveVideo();
    var live = _videos[_id];
    if (live == null || live.parentNode == null) {
      live?.remove();
      live = _createVideo(id: _id);
      _videos[_id] = live;
    }
    if (live.parentNode != null) {
      final flutter = _flutterHost();
      if (flutter != null && flutter.parentNode != null) {
        final next = live.nextElementSibling;
        if (next != flutter) {
          flutter.parentNode!.insertBefore(live, flutter);
        }
      }
    }

    live.style
      ..setProperty('left', '${offset.dx}px')
      ..setProperty('top', '${offset.dy}px')
      ..setProperty('width', '${size.width}px')
      ..setProperty('height', '${size.height}px')
      ..setProperty(
        'object-fit',
        widget.fit == BoxFit.contain ? 'contain' : 'cover',
      )
      ..setProperty('z-index', '0')
      ..setProperty('pointer-events', 'none')
      ..setProperty('clip-path', 'none')
      ..setProperty(
        'border-radius',
        widget.borderRadius > 0 ? '${widget.borderRadius}px' : '0',
      )
      ..setProperty('visibility', 'visible')
      ..setProperty('display', 'block');

    final url = widget.urls[_urlIndex.clamp(0, widget.urls.length - 1)];
    if (forceSrc || live.currentSrc.isEmpty || !_srcMatches(live, url)) {
      _bindEvents(live);
      live.muted = true;
      live.setAttribute('muted', 'true');
      live.src = url;
      live.load();
    }

    live.muted = widget.muted;
    if (widget.muted) {
      live.setAttribute('muted', 'true');
    } else {
      live.removeAttribute('muted');
    }

    if (widget.playing) {
      if (live.paused) {
        final play = live.play();
        if (play != null) {
          play.catchError((_) {});
        }
      }
    } else if (!live.paused) {
      live.pause();
    }
  }

  bool _srcMatches(html.VideoElement video, String url) {
    if (video.src == url) return true;
    final current = video.currentSrc;
    return current.isNotEmpty && (current == url || current.endsWith(url));
  }

  void _bindEvents(html.VideoElement video) {
    _errorSub?.cancel();
    _canPlaySub?.cancel();
    _canPlaySub = video.onCanPlay.listen((_) {
      video.style.setProperty('opacity', '1');
    });
    _errorSub = video.onError.listen((_) {
      if (!mounted) return;
      if (_urlIndex + 1 < widget.urls.length) {
        _urlIndex += 1;
        video.style.setProperty('opacity', '0');
        video.src = widget.urls[_urlIndex];
        video.load();
        return;
      }
      _failed = true;
      _hide();
      widget.onFailed?.call();
    });
  }

  void _hide() {
    final video = _videos[_id];
    if (video == null) return;
    video.pause();
    video.style
      ..setProperty('visibility', 'hidden')
      ..setProperty('display', 'none')
      ..setProperty('opacity', '0')
      ..setProperty('width', '0')
      ..setProperty('height', '0')
      ..setProperty('left', '-9999px');
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
