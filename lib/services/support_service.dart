// Сервис для работы с поддержкой
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SupportService {
  static const String baseUrl = 'http://localhost:5000/api/v1';
  
  /// Создать обращение в поддержку
  static Future<CreateTicketResponse> createTicket({
    required String type, // 'cancel_subscription' | 'technical_issue' | 'billing' | 'other'
    required String subject,
    required String message,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception(error['detail'] ?? 'Failed to create support ticket');
    }
  }
  
  /// Получить список обращений пользователя
  static Future<TicketsListResponse> getUserTickets({
    String? status, // 'open' | 'in_progress' | 'resolved' | 'closed'
    int limit = 20,
    int offset = 0,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception('Failed to load support tickets');
    }
  }
  
  /// Получить детали обращения
  static Future<SupportTicket> getTicket(int ticketId) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
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
      throw Exception('Failed to load ticket');
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
  
  SupportTicket({
    required this.id,
    required this.type,
    required this.subject,
    required this.message,
    required this.status,
    this.resolutionComment,
    this.createdAt,
    this.resolvedAt,
  });
  
  factory SupportTicket.fromJson(Map<String, dynamic> json) {
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
    );
  }
}

