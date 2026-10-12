import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/theme_mode_controller.dart';
import 'package:han_eat/core/theme/app_theme.dart';
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
    expect(first.state, AppThemeChoice.light);
    expect(first.state.materialMode, ThemeMode.light);

    final second = ThemeModeController();
    await second.ready;
    expect(second.state, AppThemeChoice.light);
    first.dispose();
    second.dispose();
  });

  test('setThemeMode persists system instead of forcing dark', () async {
    final first = ThemeModeController();
    await first.ready;
    await first.setThemeMode(ThemeMode.system);
    expect(first.state, AppThemeChoice.system);
    expect(first.state.materialMode, ThemeMode.system);

    final second = ThemeModeController();
    await second.ready;
    expect(second.state, AppThemeChoice.system);
    first.dispose();
    second.dispose();
  });

  test('midnight is its own choice and stays dark for Material', () async {
    final first = ThemeModeController();
    await first.ready;
    await first.setChoice(AppThemeChoice.midnight);
    expect(first.state, AppThemeChoice.midnight);
    expect(first.state.materialMode, ThemeMode.dark);

    final second = ThemeModeController();
    await second.ready;
    expect(second.state, AppThemeChoice.midnight);
    first.dispose();
    second.dispose();
  });

  test('light and midnight theme data keep opposite brightness', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.light().scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
    expect(AppTheme.dark().brightness, Brightness.dark);
    expect(AppTheme.midnight().brightness, Brightness.dark);
    expect(AppTheme.midnight().scaffoldBackgroundColor, const Color(0xFF000000));
  });

  test('parse keeps explicit light even when web prefers dark', () {
    expect(
      AppThemeChoice.parse('light', preferDark: true),
      AppThemeChoice.light,
    );
    expect(
      AppThemeChoice.parse(null, preferDark: true),
      AppThemeChoice.dark,
    );
  });
}
