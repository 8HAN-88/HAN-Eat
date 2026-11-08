import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/api_datetime.dart';
import 'package:han_eat/utils/chat_time_format.dart';

void main() {
  test('naive API timestamp is the UTC instant', () {
    final parsed = parseApiDateTime('2026-11-08T12:14:00');
    expect(parsed, isNotNull);
    expect(parsed!.toUtc(), DateTime.utc(2026, 11, 8, 12, 14));
  });

  test('Z and explicit offset stay the same instant', () {
    final naive = parseApiDateTime('2026-11-08T12:14:00');
    final zulu = parseApiDateTime('2026-11-08T12:14:00Z');
    final offset = parseApiDateTime('2026-11-08T15:14:00+03:00');
    expect(zulu!.toUtc(), naive!.toUtc());
    expect(offset!.toUtc(), naive.toUtc());
  });

  test('date-only values keep the calendar day', () {
    final day = parseApiDateTime('2026-11-08');
    expect(day, DateTime(2026, 11, 8));
  });

  test('yesterday evening is not shown as a today clock after midnight', () {
    final now = DateTime(2026, 11, 9, 0, 20);
    expect(
      formatChatMessageTime(DateTime(2026, 11, 8, 23, 40), now: now),
      '08.11',
    );
    expect(
      formatChatMessageTime(DateTime(2026, 11, 9, 0, 5), now: now),
      '00:05',
    );
  });
}
