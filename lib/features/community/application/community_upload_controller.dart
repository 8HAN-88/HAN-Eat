import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

class CommunityUploadState {
  const CommunityUploadState({
    required this.uploading,
    required this.error,
    required this.success,
  });

  factory CommunityUploadState.initial() => const CommunityUploadState(
        uploading: false,
        error: null,
        success: false,
      );

  final bool uploading;
  final String? error;
  final bool success;

  CommunityUploadState copyWith({
    bool? uploading,
    String? error,
    bool? success,
  }) {
    return CommunityUploadState(
      uploading: uploading ?? this.uploading,
      error: error,
      success: success ?? this.success,
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
    required Uint8List videoBytes,
    Uint8List? thumbnailBytes,
    String? avatar,
  }) async {
    if (state.uploading) return false;
    state = state.copyWith(uploading: true, error: null, success: false);
    try {
      final videoBase64 = base64Encode(videoBytes);
      final thumbnailBase64 =
          thumbnailBytes != null ? base64Encode(thumbnailBytes) : null;
      await ApiService.uploadCommunityVideo(
        title: title,
        author: author,
        description: description,
        tags: tags,
        videoBase64: videoBase64,
        thumbnailBase64: thumbnailBase64,
        avatar: avatar,
      );
      state = state.copyWith(uploading: false, success: true, error: null);
      return true;
    } catch (e) {
      state = state.copyWith(
        uploading: false,
        error: 'Не удалось загрузить ролик: $e',
        success: false,
      );
      return false;
    }
  }

  void reset() {
    state = CommunityUploadState.initial();
  }
}

