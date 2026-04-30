import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/analysis_mode.dart';
import '../../../services/api_service.dart';

final analysisSettingsProvider =
    StateNotifierProvider<AnalysisSettingsController, AnalysisSettingsState>(
  (ref) => AnalysisSettingsController(),
);

const supportedLanguages = <String, String>{
  'ru': 'Русский',
  'en': 'English',
  'es': 'Español',
  'de': 'Deutsch',
  'fr': 'Français',
};

String languageDisplayName(String code) {
  return supportedLanguages[code.toLowerCase()] ?? code.toUpperCase();
}

class AnalysisSettingsState {
  const AnalysisSettingsState({
    required this.mode,
    required this.language,
  });

  final AnalysisMode mode;
  final String language;

  AnalysisSettingsState copyWith({
    AnalysisMode? mode,
    String? language,
  }) {
    return AnalysisSettingsState(
      mode: mode ?? this.mode,
      language: language ?? this.language,
    );
  }
}

class AnalysisSettingsController
    extends StateNotifier<AnalysisSettingsState> {
  AnalysisSettingsController()
      : super(
          AnalysisSettingsState(
            mode: AnalysisMode.all,
            language: 'ru',
          ),
        ) {
    _init();
  }

  static const _prefsModeKey = 'analysis_mode';
  static const _prefsLangKey = 'analysis_language';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getString(_prefsModeKey);
    final storedLang = prefs.getString(_prefsLangKey);
    state = state.copyWith(
      mode: analysisModeFromString(storedMode ?? state.mode.apiValue),
      language: storedLang ?? state.language,
    );
    try {
      final remote = await ApiService.fetchSettings();
      final mode = analysisModeFromString(
        remote['analysis_mode'] as String? ?? state.mode.apiValue,
      );
      final language =
          (remote['language'] as String? ?? state.language).toLowerCase();
      state = state.copyWith(mode: mode, language: language);
      await prefs.setString(_prefsModeKey, mode.apiValue);
      await prefs.setString(_prefsLangKey, language);
    } catch (_) {
      // ignore initialization errors
    }
  }

  Future<void> changeMode(AnalysisMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsModeKey, mode.apiValue);
    try {
      await ApiService.updateSettings(mode: mode);
    } catch (_) {}
  }

  Future<void> changeLanguage(String language) async {
    final normalized = language.toLowerCase();
    state = state.copyWith(language: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLangKey, normalized);
    try {
      await ApiService.updateSettings(language: normalized);
    } catch (_) {}
  }
}

