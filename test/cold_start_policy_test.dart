import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/network/cold_start_policy.dart';

void main() {
  test('HTML boot does not wait for health before Flutter', () {
    expect(ColdStartPolicy.htmlWaitsForHealthBeforeFlutter, isFalse);
  });

  test('web /users/me restore is short', () {
    expect(
      ColdStartPolicy.webUsersMeTimeout.inSeconds,
      lessThanOrEqualTo(2),
    );
  });

  test('first Flutter retry keeps the Cache API on weak networks', () {
    expect(ColdStartPolicy.wipeCachesOnFirstFlutterRetry, isFalse);
  });

  test('session boot waits long enough for a 3G JS download', () {
    expect(
      ColdStartPolicy.htmlFirstFrameTimeoutWithSession.inSeconds,
      greaterThanOrEqualTo(60),
    );
  });

  test('updating chrome gives up so SSE cannot block the titles', () {
    expect(
      ColdStartPolicy.updatingChromeMax.inSeconds,
      lessThanOrEqualTo(10),
    );
  });

  test('HTML failBoot retry does not delete the Flutter cache', () {
    final html = File('web/index.html').readAsStringSync();
    final start = html.indexOf('function failBoot');
    final end = html.indexOf("window.addEventListener('flutter-first-frame'");
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final failBoot = html.substring(start, end);
    expect(failBoot.contains('wipeStaleFlutterCaches'), isFalse);
    expect(html.contains('hasSession() ? 90000'), isTrue);
  });
}
