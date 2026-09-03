import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/calls/call_webrtc.dart';

void main() {
  test('maps FlutterWebRTC MissingPluginException', () {
    const err =
        'MissingPluginException(No implementation found for method initialize on channel FlutterWebRTC.Method)';
    expect(CallWebrtc.isPluginMissing(err), isTrue);
    expect(
      CallWebrtc.humanError(err, video: false),
      contains('браузере'),
    );
  });

  test('maps Safari NotAllowedError', () {
    const err = 'NotAllowedError: Permission denied';
    expect(CallWebrtc.isMediaPermissionError(err), isTrue);
    expect(
      CallWebrtc.humanError(err, video: true),
      contains('камере'),
    );
  });

  test('iceLineIndex accepts JSON num and string', () {
    expect(CallWebrtc.iceLineIndex(0), 0);
    expect(CallWebrtc.iceLineIndex(1.0), 1);
    expect(CallWebrtc.iceLineIndex('2'), 2);
    expect(CallWebrtc.iceLineIndex(null), isNull);
  });

  test('peerConfiguration keeps STUN and unified-plan', () {
    final cfg = CallWebrtc.peerConfiguration(const []);
    expect(cfg['sdpSemantics'], 'unified-plan');
    expect(cfg['iceCandidatePoolSize'], 2);
    final servers = cfg['iceServers'] as List;
    expect(
      servers.any((s) => '$s'.contains('stun.l.google.com')),
      isTrue,
    );
  });

  test('video constraints stay simple for Safari fallback', () {
    final simple = CallWebrtc.videoConstraints(simple: true) as Map;
    expect(simple['facingMode'], 'user');
    expect(simple.containsKey('width'), isFalse);
  });
}
