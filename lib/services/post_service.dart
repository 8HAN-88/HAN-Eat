// Сервис для работы с постами
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class PostService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Создать пост
  static Future<Post> createPost({
    required String type,
    String? title,
    String? description,
    List<String>? tags,
    String? visibility,
    int? channelId,
    List<Map<String, String>>? media,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': type,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
        if (visibility != null) 'visibility': visibility,
        if (channelId != null) 'channel_id': channelId,
        if (media != null) 'media': media,
      }),
    );
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create post');
    }
  }
  
  /// Создать рецепт в профиле
  static Future<Post> createRecipe({
    required String title,
    String? description,
    required List<String> ingredients,
    required List<Map<String, dynamic>> steps, // [{number: int, text: String, image_url?: String}]
    List<Map<String, dynamic>>? media, // [{type: 'image'|'video', url: String}]
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
    List<String>? tags,
    String? visibility,
    int? channelId,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl/posts');
    
    final body = <String, dynamic>{
      'type': 'recipe',
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      'ingredients': ingredients,
      'steps': steps,
      if (prepTimeMin != null) 'prep_time_min': prepTimeMin,
      if (cookTimeMin != null) 'cook_time_min': cookTimeMin,
      if (servings != null) 'servings': servings,
      if (calories != null) 'calories': calories,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (media != null && media.isNotEmpty) 'media': media,
      if (visibility != null) 'visibility': visibility,
      if (channelId != null) 'channel_id': channelId,
    };

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to create recipe');
    }
  }
  
  /// Получить пост
  static Future<Post> getPost(int postId) async {
    final token = await AuthService.getAccessToken();
    
    final uri = Uri.parse('$baseUrl/posts/$postId');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.get(uri, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    } else {
      throw Exception('Failed to load post');
    }
  }
  
  /// Обновить пост
  static Future<Post> updatePost({
    required int postId,
    String? title,
    String? description,
    List<String>? tags,
    List<Map<String, String>>? media,
    List<String>? ingredients,
    List<Map<String, dynamic>>? steps,
    int? prepTimeMin,
    int? cookTimeMin,
    int? servings,
    int? calories,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId');
    final body = <String, dynamic>{};
    
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (tags != null) body['tags'] = tags;
    if (media != null) body['media'] = media;
    if (ingredients != null) body['ingredients'] = ingredients;
    if (steps != null) body['steps'] = steps;
    if (prepTimeMin != null) body['prep_time_min'] = prepTimeMin;
    if (cookTimeMin != null) body['cook_time_min'] = cookTimeMin;
    if (servings != null) body['servings'] = servings;
    if (calories != null) body['calories'] = calories;
    
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Post.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to update post');
    }
  }
}

// Временная модель поста
class Post {
  final int id;
  final String type;
  final String? title;
  final String? description;
  final String status;
  final DateTime createdAt;
  final int userId;
  final int? communityId;
  final Map<String, dynamic>? body;
  final List<String>? tags;
  
  Post({
    required this.id,
    required this.type,
    this.title,
    this.description,
    required this.status,
    required this.createdAt,
    required this.userId,
    this.communityId,
    this.body,
    this.tags,
  });
  
  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userId: json['user_id'] as int,
      communityId: json['community_id'] as int?,
      body: json['body'] as Map<String, dynamic>?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
    );
  }
}

