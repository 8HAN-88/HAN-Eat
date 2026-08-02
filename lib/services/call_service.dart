import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'api_service.dart';

class CallIceConfig {
  const CallIceConfig({
    required this.iceServers,
    required this.ringTimeoutSeconds,
  });

  final List<Map<String, dynamic>> iceServers;
  final int ringTimeoutSeconds;

  factory CallIceConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['ice_servers'];
    final servers = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          servers.add(Map<String, dynamic>.from(item));
        }
      }
    }
    if (servers.isEmpty) {
      servers.addAll(const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]);
    }
    final timeout = json['ring_timeout_seconds'];
    return CallIceConfig(
      iceServers: servers,
      ringTimeoutSeconds: timeout is int
          ? timeout
          : int.tryParse('$timeout') ?? 60,
    );
  }
}

class CallParticipantInfo {
  const CallParticipantInfo({
    required this.userId,
    required this.status,
    this.name,
    this.avatarUrl,
    this.isHost = false,
  });

  final int userId;
  final String status;
  final String? name;
  final String? avatarUrl;
  final bool isHost;

  bool get isJoined => status == 'joined';

  factory CallParticipantInfo.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return CallParticipantInfo(
      userId: asInt(json['user_id']),
      status: json['status'] as String? ?? 'invited',
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isHost: json['is_host'] as bool? ?? false,
    );
  }
}

class CallSessionInfo {
  const CallSessionInfo({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.media,
    required this.status,
    this.kind = 'direct',
    this.peerId,
    this.peerName,
    this.peerAvatarUrl,
    this.isCaller = false,
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.ringTimeoutSeconds = 60,
    this.participants = const [],
  });

  final int id;
  final int conversationId;
  final int callerId;
  final int calleeId;
  final String media;
  final String status;
  final String kind;
  final int? peerId;
  final String? peerName;
  final String? peerAvatarUrl;
  final bool isCaller;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;
  final int ringTimeoutSeconds;
  final List<CallParticipantInfo> participants;

  bool get isVideo => media == 'video';
  bool get isVoice => media != 'video';
  bool get isGroup => kind == 'group';
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

    final rawParts = json['participants'];
    final parts = <CallParticipantInfo>[];
    if (rawParts is List) {
      for (final item in rawParts) {
        if (item is Map) {
          parts.add(CallParticipantInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return CallSessionInfo(
      id: asInt(json['id']),
      conversationId: asInt(json['conversation_id']),
      callerId: asInt(json['caller_id']),
      calleeId: asInt(json['callee_id']),
      kind: json['kind'] as String? ?? 'direct',
      media: json['media'] as String? ?? 'voice',
      status: json['status'] as String? ?? 'ringing',
      peerId: json['peer_id'] == null ? null : asInt(json['peer_id']),
      peerName: json['peer_name'] as String?,
      peerAvatarUrl: json['peer_avatar_url'] as String?,
      isCaller: json['is_caller'] as bool? ?? false,
      startedAt: asDate(json['started_at']),
      endedAt: asDate(json['ended_at']),
      createdAt: asDate(json['created_at']),
      ringTimeoutSeconds: asInt(json['ring_timeout_seconds'], 60),
      participants: parts,
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

  static Future<CallIceConfig> fetchIceConfig() async {
    final response = await http.get(
      ApiService.uri('/calls/ice-servers'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      return CallIceConfig.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    // Fallback STUN so calls still try to connect offline of ICE endpoint.
    return const CallIceConfig(
      iceServers: [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      ringTimeoutSeconds: 60,
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
    int? toUserId,
  }) async {
    final response = await http.post(
      ApiService.uri('/calls/$callId/signal'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'kind': kind,
        'payload': payload,
        if (toUserId != null) 'to_user_id': toUserId,
      }),
    );
    if (response.statusCode == 200) return;
    _throw(response, 'Не удалось отправить сигнал звонка');
  }

  static Future<List<CallParticipantInfo>> participants(int callId) async {
    final response = await http.get(
      ApiService.uri('/calls/$callId/participants'),
      headers: await ApiService.authHeaders(),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = body['participants'];
      final out = <CallParticipantInfo>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            out.add(
              CallParticipantInfo.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      return out;
    }
    _throw(response, 'Не удалось загрузить участников звонка');
  }
}
