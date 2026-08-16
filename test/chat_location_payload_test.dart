import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_location_bubble.dart';

void main() {
  test('patchStoppedInContent marks a live share as stopped', () {
    final raw = ChatLocationPayload.encode(
      latitude: 55.75,
      longitude: 37.61,
      isLive: true,
      periodSeconds: 900,
      expiresAt: DateTime.utc(2026, 8, 16, 12),
    );
    final next = ChatLocationPayload.patchStoppedInContent(raw);
    final payload = ChatLocationPayload.tryParse(next)!;
    expect(payload.stopped, isTrue);
    expect(payload.isLive, isTrue);
    expect(payload.isLiveActive, isFalse);
  });

  test('patchStoppedInContent is a no-op for a static pin', () {
    final raw = ChatLocationPayload.encode(
      latitude: 55.75,
      longitude: 37.61,
    );
    expect(ChatLocationPayload.patchStoppedInContent(raw), raw);
  });
}
