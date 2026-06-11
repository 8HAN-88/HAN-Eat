import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/api_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/product_analytics.dart';
import '../../../utils/api_error_parser.dart';

class CommunityUploadState {
  const CommunityUploadState({
    required this.uploading,
    required this.error,
    required this.success,
    this.progress,
  });

  factory CommunityUploadState.initial() => const CommunityUploadState(
        uploading: false,
        error: null,
        success: false,
        progress: null,
      );

  final bool uploading;
  final String? error;
  final bool success;
  final double? progress;

  CommunityUploadState copyWith({
    bool? uploading,
    String? error,
    bool? success,
    double? progress,
  }) {
    return CommunityUploadState(
      uploading: uploading ?? this.uploading,
      error: error,
      success: success ?? this.success,
      progress: progress,
    );
  }
}

final communityUploadControllerProvider = StateNotifierProvider<
    CommunityUploadController, CommunityUploadState>(
  (ref) => CommunityUploadController(),
);

class CommunityUploadController
    extends StateNotifier<CommunityUploadState> {
  CommunityUploadController() : super(CommunityUploadState.initial());

  Future<bool> submit({
    required String title,
    required String author,
    required String description,
    required List<String> tags,
    required XFile videoFile,
    XFile? thumbnailFile,
    String? avatar,
    int? channelId,
  }) async {
    if (state.uploading) return false;
    state = state.copyWith(
      uploading: true,
      error: null,
      success: false,
      progress: 0,
    );
    try {
      final videoUpload = await MediaUploadService.uploadMediaFile(
        file: videoFile,
        fileType: 'video',
        onProgress: (value) {
          state = state.copyWith(progress: value * 0.85);
        },
      );
      final videoUrl = videoUpload.url;
      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('Не удалось загрузить видео на сервер');
      }

      String? thumbnailUrl;
      if (thumbnailFile != null) {
        final thumbUpload = await MediaUploadService.uploadMediaFile(
          file: thumbnailFile,
          fileType: 'image',
        );
        thumbnailUrl = thumbUpload.url;
      }

      state = state.copyWith(progress: 0.9);
      final video = await ApiService.uploadCommunityVideo(
        title: title,
        author: author,
        description: description,
        tags: tags,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        avatar: avatar,
        channelId: channelId,
      );
      await ProductAnalytics.logEvent(
        eventType: 'community_reel_upload',
        entityType: 'post',
        entityId: video.id,
        metadata: {'tags': tags},
      );
      state = state.copyWith(
        uploading: false,
        success: true,
        error: null,
        progress: 1,
      );
      return true;
    } on ApiClientException catch (e) {
      state = state.copyWith(
        uploading: false,
        error: e.message,
        success: false,
        progress: null,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        uploading: false,
        error: userVisibleError(e, fallback: 'Не удалось загрузить ролик'),
        success: false,
        progress: null,
      );
      return false;
    }
  }

  void reset() {
    state = CommunityUploadState.initial();
  }
}
