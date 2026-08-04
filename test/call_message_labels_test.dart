import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/calls/call_message_labels.dart';

void main() {
  group('CallMessageLabels', () {
    test('missed direct labels', () {
      final content = jsonEncode({
        'call_id': 1,
        'media': 'voice',
        'kind': 'direct',
        'status': 'missed',
        'duration_sec': 0,
      });
      expect(
        CallMessageLabels.preview(content, mine: false),
        '📞 Пропущенный звонок',
      );
      expect(
        CallMessageLabels.preview(content, mine: true),
        '📞 Звонок · без ответа',
      );
    });

    test('ended group video with duration', () {
      final content = jsonEncode({
        'call_id': 2,
        'media': 'video',
        'kind': 'group',
        'status': 'ended',
        'duration_sec': 125,
      });
      expect(
        CallMessageLabels.preview(content, mine: true),
        '📹 Групповой видеозвонок · 02:05',
      );
      expect(CallMessageLabels.isGroupOf(content), isTrue);
      expect(CallMessageLabels.mediaOf(content), 'video');
    });

    test('cancelled group voice', () {
      final content = jsonEncode({
        'call_id': 3,
        'media': 'voice',
        'call_kind': 'group',
        'status': 'cancelled',
      });
      expect(
        CallMessageLabels.preview(content, mine: false),
        '📞 Групповой звонок · отменён',
      );
    });
  });
}
