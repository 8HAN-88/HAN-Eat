import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../services/api_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/story_feed_cache.dart';
import 'story_models.dart';

class StoryService {
  static List<StoryDto> parseStoryList(dynamic data) {
    final raw = data is List
        ? data
        : (data is Map && data['items'] is List)
            ? data['items'] as List
            : const [];
    final stories = <StoryDto>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final story = StoryDto.fromJson(Map<String, dynamic>.from(item));
        if (story.isPlayable && !story.isExpired) {
          stories.add(story);
        }
      } catch (_) {}
    }
    return stories;
  }

  static Future<List<StoryDto>> fetchActiveStories({int limit = 100}) async {
    try {
      final response = await http.get(
        ApiService.uri('/stories', {'limit': '$limit'}),
        headers: await ApiService.authHeaders(),
      );
      ApiService.ensureSuccess(response);
      final stories = parseStoryList(jsonDecode(response.body));
      await StoryFeedCache.save(stories);
      return stories;
    } catch (_) {
      final cached = StoryFeedCache.peek();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  static Future<List<StoryDto>> fetchMyStories() async {
    final response = await http.get(
      ApiService.uri('/stories/mine'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    return parseStoryList(jsonDecode(response.body));
  }

  static Future<StoryDto> createStory(StoryCreateRequest request) async {
    final response = await http.post(
      ApiService.uri('/stories'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode(request.toJson()),
    );
    ApiService.ensureSuccess(response);
    return StoryDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<StoryDto> uploadAndCreateStory({
    required XFile file,
    required bool isVideo,
    String? caption,
    String visibility = 'public',
  }) async {
    final uploaded = await MediaUploadService.uploadMediaFile(
      file: file,
      fileType: isVideo ? 'video' : 'image',
      waitForProcessing: isVideo,
    );
    final mediaUrl = uploaded.url;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('Не удалось получить URL загруженного медиа');
    }
    return createStory(
      StoryCreateRequest(
        mediaUrl: mediaUrl,
        thumbnailUrl: uploaded.thumbnailUrl,
        mediaType: isVideo ? 'video' : 'image',
        caption: caption,
        visibility: visibility,
      ),
    );
  }

  static Future<StoryDto> markViewed(int storyId) async {
    final response = await http.post(
      ApiService.uri('/stories/$storyId/view'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    return StoryDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<StoryViewersPage> fetchViewers(int storyId) async {
    final response = await http.get(
      ApiService.uri('/stories/$storyId/viewers'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    return StoryViewersPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<StoryDto> setReaction({
    required int storyId,
    required String emoji,
  }) async {
    final response = await http.post(
      ApiService.uri('/stories/$storyId/reactions'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({'emoji': emoji}),
    );
    ApiService.ensureSuccess(response);
    return StoryDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<StoryDto> clearReaction(int storyId) async {
    final response = await http.delete(
      ApiService.uri('/stories/$storyId/reactions'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
    return StoryDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> deleteStory(int storyId) async {
    final response = await http.delete(
      ApiService.uri('/stories/$storyId'),
      headers: await ApiService.authHeaders(),
    );
    ApiService.ensureSuccess(response);
  }

  static List<StoryGroup> groupByAuthor(List<StoryDto> stories) {
    final map = <int, List<StoryDto>>{};
    for (final story in stories) {
      map.putIfAbsent(story.userId, () => []).add(story);
    }
    return map.values.map((items) {
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return StoryGroup(author: items.first.author, stories: items);
    }).toList()
      ..sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));
  }
}
