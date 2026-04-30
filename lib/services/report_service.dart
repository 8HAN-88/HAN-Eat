// Сервис для жалоб на контент
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ReportService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Пожаловаться на пост
  static Future<void> reportPost({
    required int postId,
    required String reason, // 'spam' | 'inappropriate' | 'copyright' | 'other'
    String? comment,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
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
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to report post');
    }
  }
  
  /// Пожаловаться на комментарий
  static Future<void> reportComment({
    required int commentId,
    required String reason,
    String? comment,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
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
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to report comment');
    }
  }
}

