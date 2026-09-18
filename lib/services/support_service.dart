// Сервис для работы с поддержкой
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class SupportService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Создать обращение в поддержку
  static Future<CreateTicketResponse> createTicket({
    required String
        type, // 'cancel_subscription' | 'technical_issue' | 'billing' | 'other'
    required String subject,
    required String message,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }

    final uri = Uri.parse('$baseUrl/support/tickets');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': type,
        'subject': subject,
        'message': message,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CreateTicketResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось создать обращение',
      );
    }
  }

  /// Получить список обращений пользователя
  static Future<TicketsListResponse> getUserTickets({
    String? status, // 'open' | 'in_progress' | 'resolved' | 'closed'
    int limit = 20,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (status != null) {
      queryParams['status'] = status;
    }

    final uri = Uri.parse('$baseUrl/support/tickets').replace(
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
      return TicketsListResponse.fromJson(data);
    } else {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить обращения',
      );
    }
  }

  /// Получить детали обращения
  static Future<SupportTicket> getTicket(int ticketId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }

    final uri = Uri.parse('$baseUrl/support/tickets/$ticketId');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SupportTicket.fromJson(data);
    } else {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось загрузить обращение',
      );
    }
  }

  static Future<List<SupportTicket>> adminTickets({
    String? status,
    int limit = 50,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    final query = <String, String>{
      'limit': '$limit',
      'offset': '0',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final response = await http.get(
      Uri.parse('$baseUrl/support/admin/tickets')
          .replace(queryParameters: query),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['tickets'] as List<dynamic>? ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(SupportTicket.fromJson)
          .toList();
    }
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: 'Не удалось загрузить очередь обращений',
    );
  }

  static Future<void> resolveTicket(
    int ticketId, {
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Войдите в аккаунт');
    }
    final response = await http.post(
      Uri.parse('$baseUrl/support/tickets/$ticketId/resolve'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (comment != null && comment.trim().isNotEmpty)
          'resolution_comment': comment.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFromHttpResponse(
        response.statusCode,
        response.body,
        fallback: 'Не удалось закрыть обращение',
      );
    }
  }
}

class CreateTicketResponse {
  final int id;
  final String type;
  final String status;
  final DateTime? createdAt;
  final String message;

  CreateTicketResponse({
    required this.id,
    required this.type,
    required this.status,
    this.createdAt,
    required this.message,
  });

  factory CreateTicketResponse.fromJson(Map<String, dynamic> json) {
    return CreateTicketResponse(
      id: json['id'] as int,
      type: json['type'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      message: json['message'] as String,
    );
  }
}

class TicketsListResponse {
  final List<SupportTicket> tickets;
  final int total;

  TicketsListResponse({
    required this.tickets,
    required this.total,
  });

  factory TicketsListResponse.fromJson(Map<String, dynamic> json) {
    return TicketsListResponse(
      tickets: (json['tickets'] as List<dynamic>)
          .map((item) => SupportTicket.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

class SupportTicket {
  final int id;
  final String type;
  final String subject;
  final String message;
  final String status;
  final String? resolutionComment;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? userName;
  final String? userEmail;
  final bool isPriority;

  SupportTicket({
    required this.id,
    required this.type,
    required this.subject,
    required this.message,
    required this.status,
    this.resolutionComment,
    this.createdAt,
    this.resolvedAt,
    this.userName,
    this.userEmail,
    this.isPriority = false,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return SupportTicket(
      id: json['id'] as int,
      type: json['type'] as String,
      subject: json['subject'] as String,
      message: json['message'] as String,
      status: json['status'] as String,
      resolutionComment: json['resolution_comment'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      userName: user?['name'] as String?,
      userEmail: user?['email'] as String?,
      isPriority: json['is_priority'] as bool? ?? false,
    );
  }
}
