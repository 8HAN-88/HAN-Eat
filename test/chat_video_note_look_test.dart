import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_video_note_bubble.dart';

void main() {
  test('video note ring keeps a circular track and sweep', () {
    final painter = ChatVideoNoteRingPainter(
      progress: 0.25,
      trackColor: const Color(0x33FFFFFF),
      progressColor: const Color(0xFFFF6B35),
    );
    expect(painter.progress, 0.25);
    expect(
      painter.shouldRepaint(
        ChatVideoNoteRingPainter(
          progress: 0.5,
          trackColor: const Color(0x33FFFFFF),
          progressColor: const Color(0xFFFF6B35),
        ),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        ChatVideoNoteRingPainter(
          progress: 0.25,
          trackColor: const Color(0x33FFFFFF),
          progressColor: const Color(0xFFFF6B35),
        ),
      ),
      isFalse,
    );
  });
}
