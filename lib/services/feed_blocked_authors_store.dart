import 'package:shared_preferences/shared_preferences.dart';

/// Локально скрываемые в ленте авторы (нет отдельного API «mute»).
class FeedBlockedAuthorsStore {
  static const _key = 'feed_blocked_user_ids';

  static Future<Set<int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  static Future<void> save(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_key);
    } else {
      final sorted = ids.toList()..sort();
      await prefs.setString(_key, sorted.join(','));
    }
  }
}
