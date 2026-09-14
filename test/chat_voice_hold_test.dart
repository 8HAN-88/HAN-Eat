import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_voice_hold.dart';

void main() {
  test('release before recorder starts still sends once ready', () {
    final session = ChatVoiceHoldSession();
    session.beginHold();
    expect(
      session.release(cancelled: false, locked: false),
      ChatVoiceHoldAction.none,
    );
    expect(session.shouldStartAfterPermission, isTrue);
    expect(session.onRecorderStarted(), ChatVoiceHoldAction.send);
  });

  test('cancel before recorder starts aborts the take', () {
    final session = ChatVoiceHoldSession();
    session.beginHold();
    session.release(cancelled: true, locked: false);
    expect(session.shouldStartAfterPermission, isFalse);
    expect(session.onRecorderStarted(), ChatVoiceHoldAction.cancel);
  });

  test('release after recording started sends immediately', () {
    final session = ChatVoiceHoldSession();
    session.beginHold();
    expect(session.onRecorderStarted(), ChatVoiceHoldAction.none);
    expect(
      session.release(cancelled: false, locked: false),
      ChatVoiceHoldAction.send,
    );
  });

  test('locked release keeps recording', () {
    final session = ChatVoiceHoldSession();
    session.beginHold();
    session.onRecorderStarted();
    expect(
      session.release(cancelled: false, locked: true),
      ChatVoiceHoldAction.none,
    );
    expect(session.recording, isTrue);
  });
}
