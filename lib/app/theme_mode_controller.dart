import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyThemeMode = 'app_theme_mode';

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController();
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  // Web social UI is neo-dark. Starting on ThemeMode.system with a light OS
  // theme paints white Material scaffolds during boot/login (= "white screen").
  ThemeModeController() : super(kIsWeb ? ThemeMode.dark : ThemeMode.system) {
    _ready = _load();
  }

  late final Future<void> _ready;
  Future<void> get ready => _ready;

  static Future<ThemeMode> _loadStored() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyThemeMode);
    if (v == null) return kIsWeb ? ThemeMode.dark : ThemeMode.system;
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return kIsWeb ? ThemeMode.dark : ThemeMode.system;
    }
  }

  Future<void> _load() async {
    state = await _loadStored();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final v = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await prefs.setString(_keyThemeMode, v);
  }
}
