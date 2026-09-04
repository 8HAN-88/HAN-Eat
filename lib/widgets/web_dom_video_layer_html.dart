import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

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
int _shieldRefs = 0;
html.DivElement? _shield;
bool _shieldListening = false;

html.Element? _flutterHost() =>
    html.document.querySelector('flt-glass-pane') ??
    html.document.querySelector('flutter-view');

void _ensureFlutterAboveVideo() {
  final flutter = html.document.querySelector('flutter-view') ??
      html.document.querySelector('flt-glass-pane');
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

Object _pointerInit({
  required num x,
  required num y,
  required int pointerId,
  required int buttons,
}) {
  final o = js_util.newObject();
  js_util.setProperty(o, 'bubbles', true);
  js_util.setProperty(o, 'cancelable', true);
  js_util.setProperty(o, 'composed', true);
  js_util.setProperty(o, 'pointerId', pointerId);
  js_util.setProperty(o, 'pointerType', 'touch');
  js_util.setProperty(o, 'isPrimary', true);
  js_util.setProperty(o, 'clientX', x);
  js_util.setProperty(o, 'clientY', y);
  js_util.setProperty(o, 'screenX', x);
  js_util.setProperty(o, 'screenY', y);
  js_util.setProperty(o, 'pageX', x);
  js_util.setProperty(o, 'pageY', y);
  js_util.setProperty(o, 'buttons', buttons);
  js_util.setProperty(o, 'button', buttons > 0 ? 0 : -1);
  js_util.setProperty(o, 'pressure', buttons > 0 ? 0.5 : 0);
  js_util.setProperty(o, 'width', 1);
  js_util.setProperty(o, 'height', 1);
  js_util.setProperty(o, 'view', html.window);
  return o;
}

void _dispatchToFlutter({
  required String type,
  required num x,
  required num y,
  required int pointerId,
  required int buttons,
}) {
  final pane = _flutterHost();
  if (pane == null) return;
  final ctor = js_util.getProperty(html.window, 'PointerEvent');
  if (ctor == null) return;
  try {
    final ev = js_util.callConstructor(ctor, [
      type,
      _pointerInit(x: x, y: y, pointerId: pointerId, buttons: buttons),
    ]);
    pane.dispatchEvent(ev as html.Event);
  } catch (_) {}
}

void _forwardPointer(html.Event raw) {
  raw.preventDefault();
  raw.stopPropagation();
  if (raw is html.PointerEvent) {
    _dispatchToFlutter(
      type: raw.type,
      x: raw.client.x,
      y: raw.client.y,
      pointerId: raw.pointerId ?? 1,
      buttons: raw.buttons ?? 0,
    );
  }
}

void _forwardTouch(html.Event raw) {
  raw.preventDefault();
  raw.stopPropagation();
  if (raw is! html.TouchEvent) return;
  final touches = raw.changedTouches;
  if (touches == null || touches.isEmpty) return;
  final t = touches[0];
  final type = switch (raw.type) {
    'touchstart' => 'pointerdown',
    'touchmove' => 'pointermove',
    'touchend' => 'pointerup',
    _ => 'pointercancel',
  };
  final buttons =
      raw.type == 'touchend' || raw.type == 'touchcancel' ? 0 : 1;
  _dispatchToFlutter(
    type: type,
    x: t.client.x,
    y: t.client.y,
    pointerId: t.identifier ?? 1,
    buttons: buttons,
  );
}

void _bindShield(html.Element shield) {
  if (_shieldListening) return;
  _shieldListening = true;
  final opts = js_util.jsify({'capture': true, 'passive': false});
  void listen(String type, void Function(html.Event) handler) {
    js_util.callMethod(shield, 'addEventListener', [
      type,
      js_util.allowInterop(handler),
      opts,
    ]);
  }

  final ua = html.window.navigator.userAgent.toLowerCase();
  final ios = ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod');
  if (ios) {
    listen('touchstart', _forwardTouch);
    listen('touchmove', _forwardTouch);
    listen('touchend', _forwardTouch);
    listen('touchcancel', _forwardTouch);
  } else {
    listen('pointerdown', _forwardPointer);
    listen('pointermove', _forwardPointer);
    listen('pointerup', _forwardPointer);
    listen('pointercancel', _forwardPointer);
  }
}

void _acquireTouchShield() {
  _shieldRefs += 1;
  if (_shield != null) return;
  final existing = html.document.getElementById('hanwe-reel-touch');
  final shield = existing is html.DivElement
      ? existing
      : (html.DivElement()..id = 'hanwe-reel-touch');
  shield.style
    ..setProperty('position', 'fixed')
    ..setProperty('left', '0')
    ..setProperty('top', '0')
    ..setProperty('right', '0')
    ..setProperty('bottom', '0')
    ..setProperty('width', '100%')
    ..setProperty('height', '100%')
    ..setProperty('z-index', '2147483646')
    ..setProperty('pointer-events', 'auto')
    ..setProperty('touch-action', 'none')
    ..setProperty('background', 'transparent');
  if (shield.parentNode == null) {
    html.document.body?.append(shield);
  }
  _shield = shield;
  _bindShield(shield);
}

void _releaseTouchShield() {
  if (_shieldRefs > 0) _shieldRefs -= 1;
  if (_shieldRefs > 0) return;
  _shield?.remove();
  _shield = null;
  _shieldListening = false;
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
    ..setProperty('-webkit-filter', 'opacity(0.999)')
    ..setProperty('margin', '0')
    ..setProperty('padding', '0')
    ..setProperty('border', 'none')
    ..setProperty('clip-path', 'none');

  final flutter = html.document.querySelector('flutter-view') ??
      html.document.querySelector('flt-glass-pane');
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
  bool _holdingShield = false;
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
    _dropShield();
    _reapOrphans();
    super.dispose();
  }

  void _holdShield() {
    if (_holdingShield) return;
    _holdingShield = true;
    _acquireTouchShield();
  }

  void _dropShield() {
    if (!_holdingShield) return;
    _holdingShield = false;
    _releaseTouchShield();
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
    _holdShield();
    var live = _videos[_id];
    if (live == null || live.parentNode == null) {
      live?.remove();
      live = _createVideo(id: _id);
      _videos[_id] = live;
    }
    if (live.parentNode != null) {
      final flutter = html.document.querySelector('flutter-view') ??
          html.document.querySelector('flt-glass-pane');
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
      video.style.setProperty('opacity', '0.999');
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
    _dropShield();
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
