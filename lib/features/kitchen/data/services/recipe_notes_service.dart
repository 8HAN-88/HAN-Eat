import 'package:shared_preferences/shared_preferences.dart';

const _prefix = 'recipe_note_';

class RecipeNotesService {
  static Future<String?> getNote(int recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$recipeId');
  }

  static Future<void> setNote(int recipeId, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await prefs.remove('$_prefix$recipeId');
    } else {
      await prefs.setString('$_prefix$recipeId', trimmed);
    }
  }

  /// Экспорт всех заметок для бэкапа: { "recipeId": "text", ... } (ключи — строки).
  static Future<Map<String, dynamic>> exportToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    final map = <String, dynamic>{};
    for (final k in keys) {
      final id = k.substring(_prefix.length);
      final v = prefs.getString(k);
      if (v != null) map[id] = v;
    }
    return map;
  }

  /// Импорт заметок из бэкапа. [data] — { "recipeId": "text", ... }. merge: true — дописать к существующим.
  static Future<void> importFromJson(Map<String, dynamic> data, {bool merge = true}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.entries) {
      final id = entry.key;
      final text = entry.value is String ? entry.value as String : entry.value?.toString() ?? '';
      if (text.isEmpty) continue;
      final key = '$_prefix$id';
      if (merge && prefs.containsKey(key)) continue; // при merge не перезаписываем
      await prefs.setString(key, text);
    }
  }
}
