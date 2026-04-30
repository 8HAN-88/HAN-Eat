// Сервис для работы с репостами
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'server_config.dart';

class RepostService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  /// Создать репост
  static Future<RepostResponse> createRepost({
    required int postId,
    String? comment,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/repost');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    );
    
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RepostResponse.fromJson(data);
    } else {
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(error['detail'] ?? 'Failed to create repost');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to create repost: ${response.statusCode}');
      }
    }
  }
  
  /// Удалить репост
  static Future<void> deleteRepost(int postId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/repost');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return;
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to delete repost');
    }
  }
  
  /// Проверить, репостнул ли пользователь пост
  static Future<bool> isPostReposted(int postId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      return false;
    }
    
    final uri = Uri.parse('$baseUrl/posts/$postId/is_reposted');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['is_reposted'] as bool? ?? false;
    } else {
      return false;
    }
  }
  
  /// Создать репост (алиас с String)
  static Future<void> repost(String postId) async {
    final postIdInt = int.tryParse(postId);
    if (postIdInt == null) throw Exception('Invalid post ID');
    await createRepost(postId: postIdInt);
  }
  
  /// Удалить репост (алиас с String)
  static Future<void> unrepost(String postId) async {
    final postIdInt = int.tryParse(postId);
    if (postIdInt == null) throw Exception('Invalid post ID');
    await deleteRepost(postIdInt);
  }
  
  /// Получить список репостов поста
  static Future<RepostsListResponse> getReposts({
    required int postId,
    int limit = 20,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessToken();
    
    final uri = Uri.parse('$baseUrl/posts/$postId/reposts').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.get(uri, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RepostsListResponse.fromJson(data);
    } else {
      throw Exception('Failed to load reposts');
    }
  }
}

class RepostResponse {
  final bool reposted;
  final int? repostId;
  final String message;
  
  RepostResponse({
    required this.reposted,
    this.repostId,
    required this.message,
  });
  
  factory RepostResponse.fromJson(Map<String, dynamic> json) {
    return RepostResponse(
      reposted: json['reposted'] as bool,
      repostId: json['repost_id'] as int?,
      message: json['message'] as String,
    );
  }
}

class RepostsListResponse {
  final List<RepostItem> reposts;
  final int total;
  
  RepostsListResponse({
    required this.reposts,
    required this.total,
  });
  
  factory RepostsListResponse.fromJson(Map<String, dynamic> json) {
    return RepostsListResponse(
      reposts: (json['reposts'] as List<dynamic>)
          .map((item) => RepostItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

class RepostItem {
  final int id;
  final RepostUser user;
  final String? comment;
  final DateTime createdAt;
  
  RepostItem({
    required this.id,
    required this.user,
    this.comment,
    required this.createdAt,
  });
  
  factory RepostItem.fromJson(Map<String, dynamic> json) {
    return RepostItem(
      id: json['id'] as int,
      user: RepostUser.fromJson(json['user'] as Map<String, dynamic>),
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class RepostUser {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  RepostUser({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  factory RepostUser.fromJson(Map<String, dynamic> json) {
    return RepostUser(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

