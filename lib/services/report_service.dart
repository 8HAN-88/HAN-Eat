// Сервис для жалоб на контент
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class ReportService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static Never _throwFromResponse(int statusCode, Map<String, dynamic> body) {
    throw apiExceptionFromResponse(
      statusCode,
      body,
      fallback: 'Не удалось отправить жалобу',
    );
  }

  /// Пожаловаться на пост
  static Future<void> reportPost({
    required int postId,
    required String reason,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw const ApiClientException(message: 'Войдите, чтобы отправить жалобу');
    }

    final uri = Uri.parse('$baseUrl/posts/$postId/report');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    );

    if (response.statusCode == 200) {
      return;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    _throwFromResponse(response.statusCode, error);
  }

  /// Пожаловаться на канал
  static Future<void> reportChannel({
    required int channelId,
    required String reason,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw const ApiClientException(message: 'Войдите, чтобы отправить жалобу');
    }

    final uri = Uri.parse('$baseUrl/channels/$channelId/report');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    );

    if (response.statusCode == 200) {
      return;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    _throwFromResponse(response.statusCode, error);
  }

  /// Пожаловаться на комментарий
  static Future<void> reportComment({
    required int commentId,
    required String reason,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw const ApiClientException(message: 'Войдите, чтобы отправить жалобу');
    }

    final uri = Uri.parse('$baseUrl/comments/$commentId/report');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    );

    if (response.statusCode == 200) {
      return;
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    _throwFromResponse(response.statusCode, error);
  }
}
