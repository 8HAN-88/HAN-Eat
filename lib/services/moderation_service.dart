// Сервис для работы с модерацией (очередь, approve/reject)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'server_config.dart';

class ModerationService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static String? _readReportComment(Map<String, dynamic> json) {
    final raw = json['report_comment'] ?? json['moderation_comment'];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Жалобы на контент (если в pending нет recent_reports — старый API).
  static Future<List<ModerationReport>> fetchContentReports({
    required String contentType,
    required int contentId,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/content-reports').replace(
      queryParameters: {
        'content_type': contentType,
        'content_id': contentId.toString(),
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
      return (data['reports'] as List<dynamic>?)
              ?.map(
                (e) => ModerationReport.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [];
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to load content reports');
  }

  static Future<ModerationListResponse> getPendingItems({
    int limit = 20,
    int offset = 0,
    String? contentType,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (contentType != null && contentType.isNotEmpty) {
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
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(error['detail'] ?? 'Failed to load moderation items');
  }

  static Future<void> approveItem({
    required int itemId,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/$itemId/approve');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({if (comment != null) 'comment': comment}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to approve item');
    }
  }

  static Future<void> hideContent({required int itemId}) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/$itemId/hide');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to hide content');
    }
  }

  static Future<void> warnUser({
    required int userId,
    String? message,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/users/$userId/warn');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({if (message != null && message.isNotEmpty) 'message': message}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to warn user');
    }
  }

  static Future<void> banUser({
    required int userId,
    String? reason,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/users/$userId/ban');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({if (reason != null && reason.isNotEmpty) 'reason': reason}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to ban user');
    }
  }

  static Future<void> rejectItem({
    required int itemId,
    required String reason,
    String? comment,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/$itemId/reject');
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

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to reject item');
    }
  }

  static ModerationResult moderateText(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) {
      return ModerationResult(isApproved: true, reason: null, flagged: false);
    }
    const suspicious = <String>[
      'viagra',
      'casino',
      'bit.ly/',
      'tinyurl.',
      't.me/',
      'telegram.me/',
      'onlyfans',
      'криптовалют',
      'заработок без вложений',
    ];
    for (final p in suspicious) {
      if (t.contains(p)) {
        return ModerationResult(
          isApproved: false,
          reason: 'Подозрительное содержимое',
          flagged: true,
        );
      }
    }
    if (RegExp(r'(.)\1{14,}').hasMatch(text)) {
      return ModerationResult(
        isApproved: false,
        reason: 'Спам (повтор символов)',
        flagged: true,
      );
    }
    return ModerationResult(
      isApproved: true,
      reason: null,
      flagged: false,
    );
  }

  static Future<ModerationDashboard> fetchDashboard() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$baseUrl/moderation/dashboard');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return ModerationDashboard.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load moderation dashboard');
  }

  static bool isModerator(String? userId) {
    if (userId == null) return false;
    final user = AuthService.instance.currentUser;
    if (user == null) return false;
    if (user.uid != userId && user.id.toString() != userId) return false;
    return user.isModerator || user.isAdmin;
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
  final int total;
  final int offset;
  final bool hasMore;

  ModerationListResponse({
    required this.items,
    required this.total,
    required this.offset,
    required this.hasMore,
  });

  factory ModerationListResponse.fromJson(Map<String, dynamic> json) {
    return ModerationListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => ModerationItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class ModerationItem {
  final int id;
  final String contentType;
  final int contentId;
  final int? userId;
  final String status;
  final String? reason;
  final String? reportCategory;
  final int? flaggedBy;
  final ModerationAuthor? flaggedByUser;
  final String? reportComment;
  final DateTime createdAt;
  final Map<String, dynamic>? contentPreview;
  final ModerationAuthor? author;
  final double? toxicityScore;
  final double? spamScore;
  final double? nsfwScore;
  final double? dangerScore;
  final String? aiDecision;
  final int reportsCount24h;
  final List<ModerationReport> recentReports;

  ModerationItem({
    required this.id,
    required this.contentType,
    required this.contentId,
    this.userId,
    required this.status,
    this.reason,
    this.reportCategory,
    this.flaggedBy,
    this.flaggedByUser,
    this.reportComment,
    required this.createdAt,
    this.contentPreview,
    this.author,
    this.toxicityScore,
    this.spamScore,
    this.nsfwScore,
    this.dangerScore,
    this.aiDecision,
    this.reportsCount24h = 0,
    this.recentReports = const [],
  });

  factory ModerationItem.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ??
        json['content_preview'] as Map<String, dynamic>?;
    final user = json['user'] as Map<String, dynamic>?;
    ModerationAuthor? author;
    if (user != null) {
      author = ModerationAuthor.fromJson(user);
    } else if (content?['author'] is Map<String, dynamic>) {
      author = ModerationAuthor.fromJson(
        content!['author'] as Map<String, dynamic>,
      );
    }

    return ModerationItem(
      id: json['id'] as int,
      contentType: json['content_type'] as String,
      contentId: json['content_id'] as int,
      userId: (json['user_id'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'pending',
      reason: json['reason'] as String?,
      reportCategory: json['report_category'] as String?,
      flaggedBy: (json['flagged_by_user_id'] as num?)?.toInt() ??
          (json['flagged_by'] as num?)?.toInt(),
      flaggedByUser: json['flagged_by_user'] is Map<String, dynamic>
          ? ModerationAuthor.fromJson(
              json['flagged_by_user'] as Map<String, dynamic>,
            )
          : null,
      reportComment: ModerationService._readReportComment(json),
      createdAt: DateTime.parse(json['created_at'] as String),
      contentPreview: content,
      author: author,
      toxicityScore: (json['toxicity_score'] as num?)?.toDouble(),
      spamScore: (json['spam_score'] as num?)?.toDouble(),
      nsfwScore: (json['nsfw_score'] as num?)?.toDouble(),
      dangerScore: (json['danger_score'] as num?)?.toDouble(),
      aiDecision: json['ai_decision'] as String?,
      reportsCount24h: (json['reports_count_24h'] as num?)?.toInt() ?? 0,
      recentReports: (json['recent_reports'] as List<dynamic>?)
              ?.map(
                (e) => ModerationReport.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }
}

class ModerationReport {
  final int id;
  final String reason;
  final String reasonLabel;
  final String? comment;
  final DateTime? createdAt;
  final ModerationAuthor? reporter;
  final String? reporterDisplayName;

  ModerationReport({
    required this.id,
    required this.reason,
    required this.reasonLabel,
    this.comment,
    this.createdAt,
    this.reporter,
    this.reporterDisplayName,
  });

  String get reporterLine =>
      reporterDisplayName ?? reporter?.displayLine ?? 'Неизвестный пользователь';

  bool get hasComment => comment != null && comment!.trim().isNotEmpty;

  factory ModerationReport.fromJson(Map<String, dynamic> json) {
    final reporterJson = json['reporter'] as Map<String, dynamic>?;
    final rawComment = json['comment'] as String?;
    final comment = rawComment != null && rawComment.trim().isNotEmpty
        ? rawComment.trim()
        : null;
    return ModerationReport(
      id: json['id'] as int,
      reason: json['reason'] as String? ?? 'other',
      reasonLabel: json['reason_label'] as String? ??
          json['reason'] as String? ??
          'other',
      comment: comment,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      reporter: reporterJson != null
          ? ModerationAuthor.fromJson(reporterJson)
          : null,
      reporterDisplayName: json['reporter_display_name'] as String?,
    );
  }
}

class ModerationDashboard {
  final int pendingTotal;
  final int pendingAutoFlagged;
  final int pendingReported;
  final int reportsLast7d;
  final int bannedUsers;
  final int shadowUsers;
  final List<ModerationAuditEntry> recentActions;

  ModerationDashboard({
    required this.pendingTotal,
    required this.pendingAutoFlagged,
    required this.pendingReported,
    required this.reportsLast7d,
    required this.bannedUsers,
    required this.shadowUsers,
    required this.recentActions,
  });

  factory ModerationDashboard.fromJson(Map<String, dynamic> json) {
    return ModerationDashboard(
      pendingTotal: (json['pending_total'] as num?)?.toInt() ?? 0,
      pendingAutoFlagged: (json['pending_auto_flagged'] as num?)?.toInt() ?? 0,
      pendingReported: (json['pending_reported'] as num?)?.toInt() ?? 0,
      reportsLast7d: (json['reports_last_7d'] as num?)?.toInt() ?? 0,
      bannedUsers: (json['banned_users'] as num?)?.toInt() ?? 0,
      shadowUsers: (json['shadow_users'] as num?)?.toInt() ?? 0,
      recentActions: (json['recent_actions'] as List<dynamic>?)
              ?.map(
                (e) => ModerationAuditEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

class ModerationAuditEntry {
  final int id;
  final String action;
  final String? contentType;
  final int? contentId;
  final String? createdAt;

  ModerationAuditEntry({
    required this.id,
    required this.action,
    this.contentType,
    this.contentId,
    this.createdAt,
  });

  factory ModerationAuditEntry.fromJson(Map<String, dynamic> json) {
    return ModerationAuditEntry(
      id: json['id'] as int,
      action: json['action'] as String,
      contentType: json['content_type'] as String?,
      contentId: (json['content_id'] as num?)?.toInt(),
      createdAt: json['created_at'] as String?,
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

  String get displayLine {
    final u = username?.trim();
    if (u != null && u.isNotEmpty) {
      return '$name (@$u)';
    }
    return name;
  }

  factory ModerationAuthor.fromJson(Map<String, dynamic> json) {
    return ModerationAuthor(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Пользователь',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
