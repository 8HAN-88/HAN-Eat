import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyThemeMode = 'app_theme_mode';

/// Visible appearance. [system] follows the OS; the rest are explicit.
enum AppThemeChoice {
  system,
  light,
  dark,
  midnight;

  ThemeMode get materialMode {
    switch (this) {
      case AppThemeChoice.system:
        return ThemeMode.system;
      case AppThemeChoice.light:
        return ThemeMode.light;
      case AppThemeChoice.dark:
      case AppThemeChoice.midnight:
        return ThemeMode.dark;
    }
  }

  String get persistValue {
    switch (this) {
      case AppThemeChoice.system:
        return 'system';
      case AppThemeChoice.light:
        return 'light';
      case AppThemeChoice.dark:
        return 'dark';
      case AppThemeChoice.midnight:
        return 'midnight';
    }
  }

  static AppThemeChoice parse(String? raw, {required bool preferDark}) {
    switch (raw) {
      case 'light':
        return AppThemeChoice.light;
      case 'dark':
        return AppThemeChoice.dark;
      case 'system':
        return AppThemeChoice.system;
      case 'midnight':
        return AppThemeChoice.midnight;
      default:
        return preferDark ? AppThemeChoice.dark : AppThemeChoice.system;
    }
  }

  static AppThemeChoice fromThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return AppThemeChoice.light;
      case ThemeMode.dark:
        return AppThemeChoice.dark;
      case ThemeMode.system:
        return AppThemeChoice.system;
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, AppThemeChoice>((ref) {
  return ThemeModeController();
});

class ThemeModeController extends StateNotifier<AppThemeChoice> {
  // Web starts dark so a light OS does not flash a white canvas before prefs.
  ThemeModeController()
      : super(kIsWeb ? AppThemeChoice.dark : AppThemeChoice.system) {
    _ready = _load();
  }

  late final Future<void> _ready;
  Future<void> get ready => _ready;

  static Future<AppThemeChoice> _loadStored() async {
    final prefs = await SharedPreferences.getInstance();
    return AppThemeChoice.parse(
      prefs.getString(_keyThemeMode),
      preferDark: kIsWeb,
    );
  }

  Future<void> _load() async {
    state = await _loadStored();
  }

  Future<void> setChoice(AppThemeChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, choice.persistValue);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      setChoice(AppThemeChoice.fromThemeMode(mode));
}
