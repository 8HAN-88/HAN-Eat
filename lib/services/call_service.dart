import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'api_service.dart';

class CallSessionInfo {
  const CallSessionInfo({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.media,
    required this.status,
    this.peerId,
    this.peerName,
    this.peerAvatarUrl,
    this.isCaller = false,
    this.startedAt,
    this.endedAt,
    this.createdAt,
  });

  final int id;
  final int conversationId;
  final int callerId;
  final int calleeId;
  final String media;
  final String status;
  final int? peerId;
  final String? peerName;
  final String? peerAvatarUrl;
  final bool isCaller;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;

  bool get isVideo => media == 'video';
  bool get isVoice => media != 'video';
  bool get isRinging => status == 'ringing';
  bool get isActive => status == 'active';
  bool get isTerminal =>
      status == 'ended' ||
      status == 'rejected' ||
      status == 'missed' ||
      status == 'cancelled';

  factory CallSessionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? asDate(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    int asInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return CallSessionInfo(
      id: asInt(json['id']),
      conversationId: asInt(json['conversation_id']),
      callerId: asInt(json['caller_id']),
      calleeId: asInt(json['callee_id']),
      media: json['media'] as String? ?? 'voice',
      status: json['status'] as String? ?? 'ringing',
      peerId: json['peer_id'] == null ? null : asInt(json['peer_id']),
      peerName: json['peer_name'] as String?,
      peerAvatarUrl: json['peer_avatar_url'] as String?,
      isCaller: json['is_caller'] as bool? ?? false,
      startedAt: asDate(json['started_at']),
      endedAt: asDate(json['ended_at']),
      createdAt: asDate(json['created_at']),
    );
  }
}

class CallService {
  static Never _throw(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  static Future<CallSessionInfo> createCall({
    required int conversationId,
    required String media,
  }) async {
    final response = await http.post(
      ApiService.uri('/calls'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'conversation_id': conversationId,
        'media': media,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось начать звонок');
  }

  static Future<CallSessionInfo> getCall(int callId) async {
    final response = await http.get(
      ApiService.uri('/calls/$callId'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось загрузить звонок');
  }

  static Future<CallSessionInfo> answer(int callId) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/answer'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось ответить на звонок');
  }

  static Future<CallSessionInfo> reject(int callId) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/reject'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось отклонить звонок');
  }

  static Future<CallSessionInfo> cancel(int callId) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/cancel'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось отменить звонок');
  }

  static Future<CallSessionInfo> end(int callId) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/end'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallSessionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось завершить звонок');
  }

  static Future<void> signal(
    int callId, {
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/signal'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'kind': kind,
        'payload': payload,
      }),
    );
    if (response.statusCode == 200) return;
    _throw(response, 'Не удалось отправить сигнал звонка');
  }
}
