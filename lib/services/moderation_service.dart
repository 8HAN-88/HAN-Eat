// Сервис для работы с модерацией
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ModerationService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Получить список элементов на модерации
  static Future<ModerationListResponse> getPendingItems({
    int limit = 20,
    String? cursor,
    String? contentType, // post | comment | user_profile
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };
    
    if (cursor != null) {
      queryParams['cursor'] = cursor;
    }
    
    if (contentType != null) {
      queryParams['content_type'] = contentType;
    }
    
    final uri = Uri.parse('$baseUrl/moderation/pending').replace(
      queryParameters: queryParams,
    );
    
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ModerationListResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to load moderation items');
    }
  }
  
  /// Одобрить элемент модерации
  static Future<void> approveItem({
    required int itemId,
    String? comment,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/moderation/$itemId/approve');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (comment != null) 'comment': comment,
      }),
    );
    
    if (response.statusCode == 200) {
      return;
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to approve item');
    }
  }
  
  /// Отклонить элемент модерации
  static Future<void> rejectItem({
    required int itemId,
    required String reason, // spam | inappropriate | copyright | other
    String? comment,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/moderation/$itemId/reject');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'reason': reason,
        if (comment != null) 'comment': comment,
      }),
    );
    
    if (response.statusCode == 200) {
      return;
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to reject item');
    }
  }
  
  /// Модерировать текст (заглушка - возвращает всегда одобрено)
  static ModerationResult moderateText(String text) {
    // TODO: Реализовать реальную модерацию через API
    return ModerationResult(
      isApproved: true,
      reason: null,
      flagged: false,
    );
  }
  
  /// Проверить, является ли пользователь модератором
  static bool isModerator(String? userId) {
    if (userId == null) return false;
    // TODO: Реализовать проверку через API или кеш
    // Временная заглушка - проверяем через AuthService
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return false;
      // Проверяем через User модель, если доступна
      return false; // По умолчанию не модератор
    } catch (e) {
      return false;
    }
  }
}

class ModerationResult {
  final bool isApproved;
  final String? reason;
  final bool flagged;
  
  ModerationResult({
    required this.isApproved,
    this.reason,
    this.flagged = false,
  });
}

class ModerationListResponse {
  final List<ModerationItem> items;
  final String? nextCursor;
  final bool hasMore;
  
  ModerationListResponse({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });
  
  factory ModerationListResponse.fromJson(Map<String, dynamic> json) {
    return ModerationListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => ModerationItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class ModerationItem {
  final int id;
  final String contentType; // post | comment | user_profile
  final int contentId;
  final int userId;
  final String status; // pending | approved | rejected
  final String? reason;
  final int? flaggedBy;
  final DateTime createdAt;
  final Map<String, dynamic>? contentPreview;
  final ModerationAuthor? author;
  
  ModerationItem({
    required this.id,
    required this.contentType,
    required this.contentId,
    required this.userId,
    required this.status,
    this.reason,
    this.flaggedBy,
    required this.createdAt,
    this.contentPreview,
    this.author,
  });
  
  factory ModerationItem.fromJson(Map<String, dynamic> json) {
    return ModerationItem(
      id: json['id'] as int,
      contentType: json['content_type'] as String,
      contentId: json['content_id'] as int,
      userId: json['user_id'] as int,
      status: json['status'] as String,
      reason: json['reason'] as String?,
      flaggedBy: json['flagged_by'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      contentPreview: json['content_preview'] as Map<String, dynamic>?,
      author: json['author'] != null
          ? ModerationAuthor.fromJson(json['author'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ModerationAuthor {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  ModerationAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  factory ModerationAuthor.fromJson(Map<String, dynamic> json) {
    return ModerationAuthor(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
