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
}
