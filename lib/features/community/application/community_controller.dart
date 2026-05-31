import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/community_video.dart';
import '../../../services/api_service.dart';
import '../../../utils/api_error_parser.dart';

class CommunityState {
  const CommunityState({
    required this.videos,
    required this.loading,
    required this.error,
    required this.activeTag,
  });

  factory CommunityState.initial() => const CommunityState(
        videos: [],
        loading: true,
        error: null,
        activeTag: null,
      );

  final List<CommunityVideo> videos;
  final bool loading;
  final String? error;
  final String? activeTag;

  CommunityState copyWith({
    List<CommunityVideo>? videos,
    bool? loading,
    String? error,
    String? activeTag,
  }) {
    return CommunityState(
      videos: videos ?? this.videos,
      loading: loading ?? this.loading,
      error: error,
      activeTag: activeTag ?? this.activeTag,
    );
  }
}

final communityControllerProvider =
    StateNotifierProvider<CommunityController, CommunityState>(
  (ref) => CommunityController(),
);

class CommunityController extends StateNotifier<CommunityState> {
  CommunityController() : super(CommunityState.initial()) {
    load();
  }

  Future<void> load({String? tag}) async {
    state = state.copyWith(loading: true, error: null, activeTag: tag);
    try {
      final videos = await ApiService.fetchCommunityVideos(tag: tag);
      state = state.copyWith(
        videos: videos,
        loading: false,
      );
    } catch (e) {
      // If backend is not available, show empty state instead of error
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('failed host lookup') || 
          errorMsg.contains('connection refused') ||
          errorMsg.contains('network') ||
          errorMsg.contains('socket')) {
        state = state.copyWith(
          videos: [],
          loading: false,
          error: null, // Don't show error for network issues
        );
      } else {
        state = state.copyWith(
          loading: false,
          error: userVisibleError(e, fallback: 'Не удалось загрузить видео'),
        );
      }
    }
  }

  Future<void> like(int id) async {
    try {
      final likes = await ApiService.likeCommunityVideo(id);
      final updated = state.videos
          .map((video) => video.id == id ? video.copyWith(likes: likes) : video)
          .toList();
      state = state.copyWith(videos: updated);
    } catch (_) {
      // игнорируем ошибки лайка
    }
  }
}

