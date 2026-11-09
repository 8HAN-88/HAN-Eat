import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/chat_time_format.dart';
import 'package:han_eat/utils/presence_format.dart';

void main() {
  test('a timestamp hours ahead is not online', () {
    final now = DateTime(2026, 11, 9, 15);
    expect(
      isRecentlyOnline(now.add(const Duration(hours: 2)), now: now),
      isFalse,
    );
    expect(
      isRecentlyOnline(now.subtract(const Duration(minutes: 2)), now: now),
      isTrue,
    );
    expect(
      isRecentlyOnline(now.add(const Duration(minutes: 2)), now: now),
      isTrue,
    );
    expect(
      formatLastSeen(now.add(const Duration(hours: 2)), now: now),
      'был(а) только что',
    );
  });

  test('yesterday is the previous calendar day, with the clock', () {
    final now = DateTime(2026, 11, 9, 10);
    expect(
      formatLastSeen(DateTime(2026, 11, 8, 23, 40), now: now),
      'был(а) вчера в 23:40',
    );
    expect(
      formatLastSeen(DateTime(2026, 11, 9, 8), now: now),
      'был(а) 2 часа назад',
    );
    expect(
      formatLastSeen(DateTime(2026, 11, 9, 0, 20), now: DateTime(2026, 11, 9, 0, 50)),
      'был(а) 30 минут назад',
    );
  });

  test('almost two elapsed days is not yesterday when the calendar moved on', () {
    final now = DateTime(2026, 11, 9, 1);
    expect(
      formatLastSeen(DateTime(2026, 11, 7, 2), now: now),
      'был(а) 2 дня назад',
    );
    expect(formatLastSeen(null, now: now), '');
  });

  test('evening preset stops saying today after 21:00', () {
    final afternoon = scheduleEveningPreset(DateTime(2026, 11, 9, 18));
    expect(afternoon.label, 'Сегодня вечером');
    expect(afternoon.at, DateTime(2026, 11, 9, 21));

    final night = scheduleEveningPreset(DateTime(2026, 11, 9, 21, 30));
    expect(night.label, 'Завтра вечером');
    expect(night.at, DateTime(2026, 11, 10, 21));
  });
}
