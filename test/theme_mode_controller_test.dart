import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setThemeMode persists light and reloads it', () async {
    final first = ThemeModeController();
    await first.ready;
    await first.setThemeMode(ThemeMode.light);
    expect(first.state, ThemeMode.light);

    final second = ThemeModeController();
    await second.ready;
    expect(second.state, ThemeMode.light);
    first.dispose();
    second.dispose();
  });

  test('setThemeMode persists system instead of forcing dark', () async {
    final first = ThemeModeController();
    await first.ready;
    await first.setThemeMode(ThemeMode.system);
    expect(first.state, ThemeMode.system);

    final second = ThemeModeController();
    await second.ready;
    expect(second.state, ThemeMode.system);
    first.dispose();
    second.dispose();
  });
}
