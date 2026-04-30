import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'api_service.dart';
import '../models/post_model.dart';

/// Сервис для полнотекстового поиска постов и рецептов
class SearchService {
  static String get baseUrl => ApiService.baseUrl + '/api/v1';

  /// Поиск постов
  static Future<SearchPostsResponse> searchPosts({
    required String query,
    String? postType, // photo | recipe | reel | text
    int? authorId,
    int? channelId,
    List<String>? tags,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? minLikes,
    int? minComments,
    String sortBy = 'relevance', // relevance | date | popularity
    int limit = 20,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessToken();
    
    final uri = Uri.parse('$baseUrl/search/posts').replace(queryParameters: {
      'q': query,
      if (postType != null) 'post_type': postType,
      if (authorId != null) 'author_id': authorId.toString(),
      if (channelId != null) 'channel_id': channelId.toString(),
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String().split('T')[0],
      if (dateTo != null) 'date_to': dateTo.toIso8601String().split('T')[0],
      if (minLikes != null) 'min_likes': minLikes.toString(),
      if (minComments != null) 'min_comments': minComments.toString(),
      'sort_by': sortBy,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SearchPostsResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to search posts');
    }
  }

  /// Поиск по рецептам
  static Future<SearchRecipesResponse> searchRecipes({
    required String query,
    int? authorId,
    List<String>? tags,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? minLikes,
    int? minComments,
    String sortBy = 'relevance',
    int limit = 20,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessToken();
    
    final uri = Uri.parse('$baseUrl/search/recipes').replace(queryParameters: {
      'q': query,
      if (authorId != null) 'author_id': authorId.toString(),
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String().split('T')[0],
      if (dateTo != null) 'date_to': dateTo.toIso8601String().split('T')[0],
      if (minLikes != null) 'min_likes': minLikes.toString(),
      if (minComments != null) 'min_comments': minComments.toString(),
      'sort_by': sortBy,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SearchRecipesResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to search recipes');
    }
  }

  /// Получить предложения для автодополнения
  static Future<List<String>> getSuggestions({
    required String query,
    int limit = 10,
  }) async {
    final uri = Uri.parse('$baseUrl/search/suggestions').replace(queryParameters: {
      'q': query,
      'limit': limit.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List<dynamic>;
      return suggestions.map((s) => s.toString()).toList();
    } else {
      return [];
    }
  }
}

class SearchPostsResponse {
  final List<PostModel> posts;
  final int total;
  final int limit;
  final int offset;

  SearchPostsResponse({
    required this.posts,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory SearchPostsResponse.fromJson(Map<String, dynamic> json) {
    return SearchPostsResponse(
      posts: (json['items'] as List<dynamic>? ?? [])
          .map((item) => PostModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 20,
      offset: json['offset'] as int? ?? 0,
    );
  }
}

class SearchRecipesResponse {
  final List<PostModel> recipes;
  final int total;
  final int limit;
  final int offset;

  SearchRecipesResponse({
    required this.recipes,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory SearchRecipesResponse.fromJson(Map<String, dynamic> json) {
    return SearchRecipesResponse(
      recipes: (json['items'] as List<dynamic>? ?? [])
          .map((item) => PostModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 20,
      offset: json['offset'] as int? ?? 0,
    );
  }
}

