import 'boot_ready_signal_stub.dart'
    if (dart.library.html) 'boot_ready_signal_web.dart' as impl;

import '../../features/reels/application/dom_video_touch_policy.dart';

void notifyPrimaryUiReady() {
  DomVideoTouchPolicy.uiInteractive = true;
  impl.notifyPrimaryUiReady();
}

void killLaunchOverlays() => impl.killLaunchOverlays();
