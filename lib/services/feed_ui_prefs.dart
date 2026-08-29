import 'package:shared_preferences/shared_preferences.dart';

import '../models/post_types.dart';

/// Последняя выбранная вкладка и фильтры ленты (между сессиями).
class FeedUiPrefs {
  FeedUiPrefs._();

  static const _tabKey = 'feed_tab_index_v2';
  static const _tabKeyV1 = 'feed_tab_index_v1';
  static const _subsFilterKey = 'feed_subs_type_v1';
  static const _recFilterKey = 'feed_rec_type_v1';
  static const _recSortKey = 'feed_rec_sort_v1';
  static const _subsSortKey = 'feed_subs_sort_v1';
  static const _reelsFollowingKey = 'feed_reels_following_v1';
  static const _homeFollowingKey = 'feed_home_following_v1';

  static String _normalizeFeedType(String? value) {
    if (value == 'recipes') return 'all';
    return value ?? 'all';
  }

  static Future<int> loadTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final v2 = prefs.getInt(_tabKey);
    if (v2 != null) return v2.clamp(0, 1);
    final v1 = prefs.getInt(_tabKeyV1);
    if (v1 == 2) return 1;
    return 0;
  }

  static Future<void> saveTabIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tabKey, index.clamp(0, 1));
  }

  static Future<bool> loadHomeFollowingOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_homeFollowingKey) ?? true;
  }

  static Future<void> saveHomeFollowingOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeFollowingKey, value);
  }

  static Future<String> loadSubsFeedType() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeFeedType(prefs.getString(_subsFilterKey));
  }

  static Future<String> loadRecFeedType() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeFeedType(prefs.getString(_recFilterKey));
  }

  static Future<FeedSortMode> loadRecSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    return FeedSortMode.fromString(prefs.getString(_recSortKey)) ??
        FeedSortMode.personalized;
  }

  static Future<FeedSortMode> loadSubsSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    return FeedSortMode.fromString(prefs.getString(_subsSortKey)) ??
        FeedSortMode.recent;
  }

  static Future<bool> loadReelsFollowingOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reelsFollowingKey) ?? false;
  }

  static Future<void> saveSubsFeedType(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subsFilterKey, _normalizeFeedType(value));
  }

  static Future<void> saveRecFeedType(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recFilterKey, _normalizeFeedType(value));
  }

  static Future<void> saveRecSortMode(FeedSortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recSortKey, mode.value);
  }

  static Future<void> saveSubsSortMode(FeedSortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subsSortKey, mode.value);
  }

  static Future<void> saveReelsFollowingOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reelsFollowingKey, value);
  }
}
