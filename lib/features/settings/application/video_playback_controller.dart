import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/video_quality_preference.dart';

final videoPlaybackProvider =
    StateNotifierProvider<VideoPlaybackController, VideoQualityPreference>(
  (ref) => VideoPlaybackController(),
);

class VideoPlaybackController extends StateNotifier<VideoQualityPreference> {
  VideoPlaybackController() : super(VideoQualityPreference.auto) {
    _load();
  }

  static const _prefsKey = 'video_quality_preference_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = VideoQualityPreferenceX.fromString(prefs.getString(_prefsKey));
  }

  Future<void> setPreference(VideoQualityPreference value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.storageValue);
  }
}
