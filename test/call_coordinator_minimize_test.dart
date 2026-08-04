import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/calls/presentation/call_coordinator.dart';

void main() {
  test('minimize/expand are no-ops without hosted overlay', () {
    final c = CallCoordinator.instance;
    expect(c.hasHostedCallUi, isFalse);
    expect(c.minimized.value, isFalse);

    c.minimizeCall();
    expect(c.minimized.value, isFalse);

    c.expandCall();
    expect(c.minimized.value, isFalse);

    c.closeCallUi();
    expect(c.hasHostedCallUi, isFalse);
  });
}
