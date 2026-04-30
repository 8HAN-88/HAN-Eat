// Сервис для работы с аналитикой
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class AnalyticsService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Получить аналитику поста
  static Future<PostAnalyticsResponse> getPostAnalytics({
    required int postId,
    int days = 30,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/analytics/posts/$postId').replace(
      queryParameters: {
        'days': days.toString(),
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
      return PostAnalyticsResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to load post analytics');
    }
  }
  
  /// Получить аналитику профиля
  static Future<ProfileAnalyticsResponse> getProfileAnalytics({
    int days = 30,
  }) async {
    var token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated. Please log in first.');
    }
    
    final uri = Uri.parse('$baseUrl/analytics/profile').replace(
      queryParameters: {
        'days': days.toString(),
      },
    );
    
    var response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    // Если получили 401, пытаемся обновить токен и повторить запрос
    if (response.statusCode == 401) {
      try {
        token = await AuthService.refreshToken();
        response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      } catch (e) {
        throw Exception('Authentication failed. Please log in again.');
      }
    }
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ProfileAnalyticsResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(error?['detail'] ?? 'Failed to load profile analytics: ${response.statusCode}');
    }
  }
}

class PostAnalyticsResponse {
  final int postId;
  final int viewsTotal;
  final int viewsUnique;
  final List<DailyCount> viewsByDay;
  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final int repostsCount;
  final double ctr;
  final double engagementRate;
  final int? avgViewDurationSec;
  final Map<String, dynamic>? demographics;
  
  PostAnalyticsResponse({
    required this.postId,
    required this.viewsTotal,
    required this.viewsUnique,
    required this.viewsByDay,
    required this.likesCount,
    required this.commentsCount,
    required this.savesCount,
    required this.repostsCount,
    required this.ctr,
    required this.engagementRate,
    this.avgViewDurationSec,
    this.demographics,
  });
  
  factory PostAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    // Поддержка двух форматов: новый (из backend) и старый (для совместимости)
    if (json.containsKey('views_total')) {
      // Новый формат
      return PostAnalyticsResponse(
        postId: json['post_id'] as int,
        viewsTotal: json['views_total'] as int,
        viewsUnique: json['views_unique'] as int,
        viewsByDay: (json['views_by_day'] as List<dynamic>)
            .map((item) => DailyCount.fromJson(item as Map<String, dynamic>))
            .toList(),
        likesCount: json['likes_count'] as int,
        commentsCount: json['comments_count'] as int,
        savesCount: json['saves_count'] as int,
        repostsCount: json['reposts_count'] as int,
        ctr: (json['ctr'] as num).toDouble(),
        engagementRate: (json['engagement_rate'] as num).toDouble(),
        avgViewDurationSec: json['avg_view_duration_sec'] as int?,
        demographics: json['demographics'] as Map<String, dynamic>?,
      );
    } else {
      // Старый формат (из существующего analytics_service.dart)
      final views = json['views'] as Map<String, dynamic>;
      final engagement = json['engagement'] as Map<String, dynamic>;
      final metrics = json['metrics'] as Map<String, dynamic>;
      return PostAnalyticsResponse(
        postId: json['post_id'] as int,
        viewsTotal: views['total'] as int,
        viewsUnique: views['unique'] as int,
        viewsByDay: (json['by_day'] as List<dynamic>)
            .map((item) {
              final itemMap = item as Map<String, dynamic>;
              return DailyCount(
                date: itemMap['date'] != null
                    ? DateTime.parse(itemMap['date'] as String)
                    : DateTime.now(),
                count: itemMap['count'] as int,
              );
            })
            .toList(),
        likesCount: engagement['likes'] as int,
        commentsCount: engagement['comments'] as int,
        savesCount: engagement['saves'] as int,
        repostsCount: engagement['reposts'] as int,
        ctr: (metrics['ctr'] as num).toDouble(),
        engagementRate: (metrics['engagement_rate'] as num).toDouble(),
        avgViewDurationSec: null,
        demographics: null,
      );
    }
  }
}

class ProfileAnalyticsResponse {
  final int userId;
  final int totalViews;
  final int totalLikes;
  final int totalComments;
  final int totalSaves;
  final int totalReposts;
  final int postsCount;
  final int channelsCount;
  final int followersCount;
  final List<PostAnalyticsResponse> topPosts;
  final List<DailyCount> viewsByDay;
  final double avgEngagementRate;
  final Map<String, dynamic>? demographics;
  
  ProfileAnalyticsResponse({
    required this.userId,
    required this.totalViews,
    required this.totalLikes,
    required this.totalComments,
    required this.totalSaves,
    required this.totalReposts,
    required this.postsCount,
    required this.channelsCount,
    required this.followersCount,
    required this.topPosts,
    required this.viewsByDay,
    required this.avgEngagementRate,
    this.demographics,
  });
  
  factory ProfileAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    try {
      // Поддержка двух форматов: новый (из backend) и старый (для совместимости)
      if (json.containsKey('total_views') && !json.containsKey('total_engagement')) {
        // Новый формат (с отдельными полями)
        return ProfileAnalyticsResponse(
          userId: json['user_id'] as int,
          totalViews: json['total_views'] as int? ?? 0,
          totalLikes: json['total_likes'] as int? ?? 0,
          totalComments: json['total_comments'] as int? ?? 0,
          totalSaves: json['total_saves'] as int? ?? 0,
          totalReposts: json['total_reposts'] as int? ?? 0,
          postsCount: json['posts_count'] as int? ?? 0,
          channelsCount: json['channels_count'] as int? ?? 0,
          followersCount: json['followers_count'] as int? ?? 0,
          topPosts: (json['top_posts'] as List<dynamic>?)
                  ?.map((item) {
                    // Преобразуем упрощенную версию топ поста в PostAnalyticsResponse
                    final itemMap = item as Map<String, dynamic>;
                    return PostAnalyticsResponse(
                      postId: itemMap['post_id'] as int,
                      viewsTotal: itemMap['views_total'] as int? ?? 0,
                      viewsUnique: itemMap['views_unique'] as int? ?? 0,
                      viewsByDay: [],
                      likesCount: itemMap['likes_count'] as int? ?? 0,
                      commentsCount: itemMap['comments_count'] as int? ?? 0,
                      savesCount: itemMap['saves_count'] as int? ?? 0,
                      repostsCount: itemMap['reposts_count'] as int? ?? 0,
                      ctr: (itemMap['ctr'] as num?)?.toDouble() ?? 0.0,
                      engagementRate: (itemMap['engagement_rate'] as num?)?.toDouble() ?? 0.0,
                      avgViewDurationSec: null,
                      demographics: null,
                    );
                  })
                  .toList() ??
              [],
          viewsByDay: (json['views_by_day'] as List<dynamic>?)
                  ?.map((item) => DailyCount.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [],
          avgEngagementRate: (json['avg_engagement_rate'] as num?)?.toDouble() ?? 0.0,
          demographics: json['demographics'] as Map<String, dynamic>?,
        );
      } else {
        // Старый формат (с total_engagement как словарь)
        final totalEngagement = json['total_engagement'] as Map<String, dynamic>? ?? {};
        return ProfileAnalyticsResponse(
          userId: json['user_id'] as int,
          totalViews: json['total_views'] as int? ?? 0,
          totalLikes: totalEngagement['likes'] as int? ?? 0,
          totalComments: totalEngagement['comments'] as int? ?? 0,
          totalSaves: totalEngagement['saves'] as int? ?? 0,
          totalReposts: totalEngagement['reposts'] as int? ?? 0,
          postsCount: json['posts_count'] as int? ?? 0,
          channelsCount: json['channels_count'] as int? ?? 0,
          followersCount: json['followers_count'] as int? ?? 0,
          topPosts: (json['top_posts'] as List<dynamic>?)
                  ?.map((item) {
                    final itemMap = item as Map<String, dynamic>;
                    return PostAnalyticsResponse(
                      postId: itemMap['post_id'] as int,
                      viewsTotal: itemMap['views'] as int? ?? itemMap['views_total'] as int? ?? 0,
                      viewsUnique: itemMap['views_unique'] as int? ?? 0,
                      viewsByDay: [],
                      likesCount: itemMap['likes'] as int? ?? itemMap['likes_count'] as int? ?? 0,
                      commentsCount: itemMap['comments'] as int? ?? itemMap['comments_count'] as int? ?? 0,
                      savesCount: itemMap['saves'] as int? ?? itemMap['saves_count'] as int? ?? 0,
                      repostsCount: itemMap['reposts'] as int? ?? itemMap['reposts_count'] as int? ?? 0,
                      ctr: (itemMap['ctr'] as num?)?.toDouble() ?? 0.0,
                      engagementRate: (itemMap['engagement_rate'] as num?)?.toDouble() ?? 0.0,
                      avgViewDurationSec: null,
                      demographics: null,
                    );
                  })
                  .toList() ??
              [],
          viewsByDay: (json['by_day'] as List<dynamic>?)
                  ?.map((item) {
                    final itemMap = item as Map<String, dynamic>;
                    return DailyCount(
                      date: itemMap['date'] != null
                          ? DateTime.parse(itemMap['date'] as String)
                          : DateTime.now(),
                      count: itemMap['count'] as int? ?? 0,
                    );
                  })
                  .toList() ??
              [],
          avgEngagementRate: 0.0,
          demographics: null,
        );
      }
    } catch (e) {
      // Если произошла ошибка парсинга, возвращаем пустой ответ
      print('Ошибка парсинга аналитики профиля: $e');
      print('JSON: $json');
      return ProfileAnalyticsResponse(
        userId: json['user_id'] as int? ?? 0,
        totalViews: 0,
        totalLikes: 0,
        totalComments: 0,
        totalSaves: 0,
        totalReposts: 0,
        postsCount: 0,
        channelsCount: 0,
        followersCount: 0,
        topPosts: [],
        viewsByDay: [],
        avgEngagementRate: 0.0,
        demographics: null,
      );
    }
  }
}

class DailyCount {
  final DateTime date;
  final int count;
  
  DailyCount({
    required this.date,
    required this.count,
  });
  
  factory DailyCount.fromJson(Map<String, dynamic> json) {
    return DailyCount(
      date: DateTime.parse(json['date'] as String),
      count: json['count'] as int,
    );
  }
}
