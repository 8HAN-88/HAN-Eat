// Сервис для работы с уведомлениями
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class NotificationService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  // Singleton instance
  static final NotificationService instance = NotificationService._();
  NotificationService._();
  
  /// Инициализация сервиса
  static Future<void> init() async {
    // Пока ничего не делаем при инициализации
  }
  
  /// Отменить уведомление (заглушка)
  Future<void> cancelNotification(String id) async {
    // TODO: Реализовать отмену уведомления
  }
  
  /// Запланировать уведомление (заглушка)
  Future<void> scheduleNotification({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // TODO: Реализовать планирование уведомления
  }
  
  /// Получить список уведомлений
  static Future<NotificationsResponse> getNotifications({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/notifications').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'unread_only': unreadOnly.toString(),
      },
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
      return NotificationsResponse.fromJson(data);
    } else {
      throw Exception('Failed to load notifications');
    }
  }
  
  /// Пометить уведомление как прочитанное/непрочитанное
  static Future<void> markAsRead({
    required int notificationId,
    bool read = true,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/notifications/$notificationId/read');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'read': read,
      }),
    );
    
    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception('Failed to mark notification as read');
    }
  }
  
  /// Пометить все уведомления как прочитанные
  static Future<void> markAllAsRead() async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/notifications/read-all');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception('Failed to mark all notifications as read');
    }
  }
  
  /// Получить количество непрочитанных уведомлений
  static Future<int> getUnreadCount() async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      return 0;
    }
    
    final uri = Uri.parse('$baseUrl/notifications/unread-count');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['unread_count'] as int? ?? 0;
    } else {
      return 0;
    }
  }
}

class NotificationsResponse {
  final List<NotificationItem> notifications;
  final int unreadCount;
  final bool hasMore;
  
  NotificationsResponse({
    required this.notifications,
    required this.unreadCount,
    required this.hasMore,
  });
  
  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    return NotificationsResponse(
      notifications: (json['notifications'] as List<dynamic>)
          .map((item) => NotificationItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      unreadCount: json['unread_count'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String? body;
  final String? entityType;
  final int? entityId;
  final NotificationActor? actor;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;
  final Map<String, dynamic>? data;
  
  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.entityType,
    this.entityId,
    this.actor,
    required this.isRead,
    this.readAt,
    this.createdAt,
    this.data,
  });
  
  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      entityType: json['entity_type'] as String?,
      entityId: json['entity_id'] as int?,
      actor: json['actor'] != null
          ? NotificationActor.fromJson(json['actor'] as Map<String, dynamic>)
          : null,
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}

class NotificationActor {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  NotificationActor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  factory NotificationActor.fromJson(Map<String, dynamic> json) {
    return NotificationActor(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
