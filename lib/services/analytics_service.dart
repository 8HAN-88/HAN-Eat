import 'package:flutter/foundation.dart';
// Сервис для работы с аналитикой
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'server_config.dart';

class AnalyticsService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  /// Получить аналитику поста
  static Future<PostAnalyticsResponse> getPostAnalytics({
    required int postId,
    int days = 30,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
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
    var token = await AuthService.getAccessTokenForApi();
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

/// Строка «топ постов» в аналитике профиля (не путать с полной аналитикой поста).
class ProfileTopPostSummary {
  final int postId;
  final String title;
  final int views;
  final int likes;
  final int comments;
  final int saves;
  final int reposts;
  /// Доля реакций к просмотрам этого поста за период, 0–100.
  final double engagementRatePercent;

  ProfileTopPostSummary({
    required this.postId,
    required this.title,
    required this.views,
    required this.likes,
    required this.comments,
    required this.saves,
    required this.reposts,
    required this.engagementRatePercent,
  });

  factory ProfileTopPostSummary.fromJson(Map<String, dynamic> m) {
    final views = (m['views'] as num?)?.toInt() ??
        (m['views_total'] as num?)?.toInt() ??
        0;
    final likes = (m['likes'] as num?)?.toInt() ??
        (m['likes_count'] as num?)?.toInt() ??
        0;
    final comments = (m['comments'] as num?)?.toInt() ??
        (m['comments_count'] as num?)?.toInt() ??
        0;
    final saves = (m['saves'] as num?)?.toInt() ??
        (m['saves_count'] as num?)?.toInt() ??
        0;
    final reposts = (m['reposts'] as num?)?.toInt() ??
        (m['reposts_count'] as num?)?.toInt() ??
        0;
    final fromApi = (m['engagement_rate'] as num?)?.toDouble();
    final reactions = likes + comments + saves + reposts;
    final computed =
        views > 0 ? (reactions / views * 100) : 0.0;
    return ProfileTopPostSummary(
      postId: (m['post_id'] as num).toInt(),
      title: (m['title'] as String?)?.trim() ?? '',
      views: views,
      likes: likes,
      comments: comments,
      saves: saves,
      reposts: reposts,
      engagementRatePercent: fromApi ?? computed,
    );
  }
}

class ProfileAnalyticsResponse {
  final int userId;
  final int periodDays;
  final int totalViews;
  final int totalLikes;
  final int totalComments;
  final int totalSaves;
  final int totalReposts;
  final int postsCount;
  final int channelsCount;
  final int followersCount;
  final List<ProfileTopPostSummary> topPosts;
  final List<DailyCount> viewsByDay;
  /// Реакции к просмотрам по всем постам за период, 0–100.
  final double engagementRatePercent;
  final Map<String, dynamic>? demographics;

  ProfileAnalyticsResponse({
    required this.userId,
    required this.periodDays,
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
    required this.engagementRatePercent,
    this.demographics,
  });

  factory ProfileAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    try {
      final totalEngagement =
          json['total_engagement'] as Map<String, dynamic>? ?? {};
      int readInt(dynamic v) => (v as num?)?.toInt() ?? 0;

      final topRaw = json['top_posts'] as List<dynamic>? ?? [];
      final topPosts = topRaw
          .map((item) =>
              ProfileTopPostSummary.fromJson(item as Map<String, dynamic>))
          .toList();

      final byDayRaw = json['by_day'] as List<dynamic>? ??
          json['views_by_day'] as List<dynamic>? ??
          [];

      final totalViews = readInt(json['total_views']);
      final totalLikes = readInt(totalEngagement['likes']);
      final totalComments = readInt(totalEngagement['comments']);
      final totalSaves = readInt(totalEngagement['saves']);
      final totalReposts = readInt(totalEngagement['reposts']);
      final reactionsSum =
          totalLikes + totalComments + totalSaves + totalReposts;
      final periodDays = readInt(json['period_days']);
      final rawEr = json['engagement_rate'];
      final engagementRate = rawEr is num
          ? rawEr.toDouble()
          : (totalViews > 0 ? (reactionsSum / totalViews * 100) : 0.0);

      return ProfileAnalyticsResponse(
        userId: readInt(json['user_id']),
        periodDays: periodDays > 0 ? periodDays : 30,
        totalViews: totalViews,
        totalLikes: totalLikes,
        totalComments: totalComments,
        totalSaves: totalSaves,
        totalReposts: totalReposts,
        postsCount: readInt(json['posts_count']),
        channelsCount: readInt(json['channels_count']),
        followersCount: readInt(json['followers_count']),
        topPosts: topPosts,
        viewsByDay: byDayRaw.map((item) {
          final itemMap = item as Map<String, dynamic>;
          return DailyCount(
            date: itemMap['date'] != null
                ? DateTime.parse(itemMap['date'] as String)
                : DateTime.now(),
            count: readInt(itemMap['count']),
          );
        }).toList(),
        engagementRatePercent: engagementRate,
        demographics: json['demographics'] as Map<String, dynamic>?,
      );
    } catch (e) {
      debugPrint('Ошибка парсинга аналитики профиля: $e');
      debugPrint('JSON: $json');
      return ProfileAnalyticsResponse(
        userId: readIntSafe(json['user_id']),
        periodDays: 30,
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
        engagementRatePercent: 0.0,
        demographics: null,
      );
    }
  }
}

int readIntSafe(dynamic v) => (v as num?)?.toInt() ?? 0;

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
