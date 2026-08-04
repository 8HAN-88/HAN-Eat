import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/calls/call_media_controls.dart';
import 'package:han_eat/services/user_realtime_service.dart';

void main() {
  group('CallMediaControls event parsing', () {
    test('muteFromEvent', () {
      final on = UserRealtimeEvent(
        event: 'call.signal',
        signalKind: 'mute',
        signalPayload: {'muted': true},
      );
      final off = UserRealtimeEvent(
        event: 'call.signal',
        signalKind: 'mute',
        signalPayload: {'muted': 'false'},
      );
      expect(CallMediaControls.muteFromEvent(on), isTrue);
      expect(CallMediaControls.muteFromEvent(off), isFalse);
      expect(
        CallMediaControls.muteFromEvent(
          const UserRealtimeEvent(event: 'call.signal', signalKind: 'ice'),
        ),
        isNull,
      );
    });

    test('cameraOffFromEvent', () {
      final event = UserRealtimeEvent(
        event: 'call.signal',
        signalKind: 'camera',
        signalPayload: {'off': true},
      );
      expect(CallMediaControls.cameraOffFromEvent(event), isTrue);
    });
  });
}
