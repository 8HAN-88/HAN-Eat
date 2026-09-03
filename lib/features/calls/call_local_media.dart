import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_webrtc.dart';

/// Holds a local media stream captured on the user's tap (Safari gesture)
/// until [CallScreen] / [GroupCallScreen] takes it.
class CallLocalMedia {
  CallLocalMedia._();

  static MediaStream? _held;

  static MediaStream? take() {
    final stream = _held;
    _held = null;
    return stream;
  }

  static Future<void> disposeHeld() async {
    final stream = take();
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }

  static Future<MediaStream> acquire({required bool video}) async {
    await disposeHeld();
    final stream = await CallWebrtc.getUserMediaSafe(video: video);
    _held = stream;
    return stream;
  }
}
