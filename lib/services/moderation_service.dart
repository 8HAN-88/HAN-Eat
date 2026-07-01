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

  static Future<BotWebhookOpsPage> fetchWebhookOperations({
    int limit = 20,
    int offset = 0,
    String? query,
    String? eventType,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (eventType != null && eventType.trim().isNotEmpty)
        'event_type': eventType.trim(),
    };
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/ops')
        .replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return BotWebhookOpsPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load webhook operations');
  }

  static Future<BotWebhookOpsExport> exportWebhookOperations({
    int limit = 500,
    String? query,
    String? eventType,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final params = <String, String>{
      'limit': '$limit',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (eventType != null && eventType.trim().isNotEmpty)
        'event_type': eventType.trim(),
    };
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/ops/export')
        .replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return BotWebhookOpsExport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to export webhook operations');
  }

  static Future<BotWebhookOpsExport> exportWebhookIncidentReport({
    int limit = 200,
    String? query,
    String? eventType,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final params = <String, String>{
      'limit': '$limit',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (eventType != null && eventType.trim().isNotEmpty)
        'event_type': eventType.trim(),
    };
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/ops/incident-report')
        .replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return BotWebhookOpsExport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to export webhook incident report');
  }

  static Future<BotWebhookQueueStats> promoteWebhookDelayed({
    int limit = 500,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/promote-delayed');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'limit': limit}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to promote delayed webhooks');
  }

  static Future<BotWebhookQueueStats> clearWebhookQueue({
    bool includeDelayed = true,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/clear');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'include_delayed': includeDelayed}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to clear webhook queue');
  }

  static Future<BotWebhookQueueStats> resetWebhookMetrics() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/reset-metrics');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to reset webhook metrics');
  }

  static Future<BotWebhookQueueStats> requeueWebhookDeadLetters({
    int limit = 100,
    List<String>? taskIds,
    String? query,
    String? dropReason,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse(
      '$baseUrl/moderation/system/webhooks/dead-letter/requeue',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'limit': limit,
        if (taskIds != null && taskIds.isNotEmpty) 'task_ids': taskIds,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (dropReason != null && dropReason.trim().isNotEmpty)
          'drop_reason': dropReason.trim(),
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to requeue dead-letter webhooks');
  }

  static Future<BotWebhookDeadLetterPage> fetchWebhookDeadLetters({
    int limit = 50,
    int offset = 0,
    String? query,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
    };
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/dead-letter')
        .replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return BotWebhookDeadLetterPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to fetch dead-letter webhooks');
  }

  static Future<BotWebhookQueueStats> clearWebhookDeadLetters() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/dead-letter/clear');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to clear dead-letter webhooks');
  }

  static Future<BotWebhookQueueStats> runWebhookRecoveryPlaybook({
    int requeueDeadLimit = 300,
    int promoteDelayedLimit = 500,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('$baseUrl/moderation/system/webhooks/recovery-playbook');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'requeue_dead_limit': requeueDeadLimit,
        'promote_delayed_limit': promoteDelayedLimit,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BotWebhookQueueStats.fromJson(
        data['stats'] as Map<String, dynamic>? ?? const {},
      );
    }
    throw Exception('Failed to run webhook recovery playbook');
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
  final BotWebhookQueueStats? botWebhookQueue;
  final BotWebhookAlerts? botWebhookAlerts;
  final List<BotWebhookOperation> botWebhookRecentOps;

  ModerationDashboard({
    required this.pendingTotal,
    required this.pendingAutoFlagged,
    required this.pendingReported,
    required this.reportsLast7d,
    required this.bannedUsers,
    required this.shadowUsers,
    required this.recentActions,
    this.botWebhookQueue,
    this.botWebhookAlerts,
    this.botWebhookRecentOps = const [],
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
      botWebhookQueue: json['bot_webhook_queue'] is Map<String, dynamic>
          ? BotWebhookQueueStats.fromJson(
              json['bot_webhook_queue'] as Map<String, dynamic>,
            )
          : null,
      botWebhookAlerts: json['bot_webhook_alerts'] is Map<String, dynamic>
          ? BotWebhookAlerts.fromJson(
              json['bot_webhook_alerts'] as Map<String, dynamic>,
            )
          : null,
      botWebhookRecentOps: ((json['bot_webhook_recent_ops'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BotWebhookOperation.fromJson)
          .toList(),
    );
  }

  ModerationDashboard copyWith({
    int? pendingTotal,
    int? pendingAutoFlagged,
    int? pendingReported,
    int? reportsLast7d,
    int? bannedUsers,
    int? shadowUsers,
    List<ModerationAuditEntry>? recentActions,
    BotWebhookQueueStats? botWebhookQueue,
    BotWebhookAlerts? botWebhookAlerts,
    List<BotWebhookOperation>? botWebhookRecentOps,
  }) {
    return ModerationDashboard(
      pendingTotal: pendingTotal ?? this.pendingTotal,
      pendingAutoFlagged: pendingAutoFlagged ?? this.pendingAutoFlagged,
      pendingReported: pendingReported ?? this.pendingReported,
      reportsLast7d: reportsLast7d ?? this.reportsLast7d,
      bannedUsers: bannedUsers ?? this.bannedUsers,
      shadowUsers: shadowUsers ?? this.shadowUsers,
      recentActions: recentActions ?? this.recentActions,
      botWebhookQueue: botWebhookQueue ?? this.botWebhookQueue,
      botWebhookAlerts: botWebhookAlerts ?? this.botWebhookAlerts,
      botWebhookRecentOps: botWebhookRecentOps ?? this.botWebhookRecentOps,
    );
  }
}

class BotWebhookOperation {
  final int id;
  final String eventType;
  final String? createdAt;
  final int? userId;
  final String? actorName;
  final String? actorUsername;
  final Map<String, dynamic> metadata;

  BotWebhookOperation({
    required this.id,
    required this.eventType,
    this.createdAt,
    this.userId,
    this.actorName,
    this.actorUsername,
    this.metadata = const {},
  });

  factory BotWebhookOperation.fromJson(Map<String, dynamic> json) {
    return BotWebhookOperation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      eventType: json['event_type'] as String? ?? 'bot_webhook_unknown',
      createdAt: json['created_at'] as String?,
      userId: (json['user_id'] as num?)?.toInt(),
      actorName: json['actor_name'] as String?,
      actorUsername: json['actor_username'] as String?,
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const {},
    );
  }
}

class BotWebhookOpsPage {
  final List<BotWebhookOperation> items;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;
  final int? nextOffset;

  BotWebhookOpsPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
    this.nextOffset,
  });

  factory BotWebhookOpsPage.fromJson(Map<String, dynamic> json) {
    return BotWebhookOpsPage(
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BotWebhookOperation.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
      hasMore: json['has_more'] == true,
      nextOffset: (json['next_offset'] as num?)?.toInt(),
    );
  }
}

class BotWebhookOpsExport {
  final int count;
  final bool truncated;
  final String content;

  BotWebhookOpsExport({
    required this.count,
    required this.truncated,
    required this.content,
  });

  factory BotWebhookOpsExport.fromJson(Map<String, dynamic> json) {
    return BotWebhookOpsExport(
      count: (json['count'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] == true,
      content: json['content'] as String? ?? '',
    );
  }
}

class BotWebhookDeadLetterItem {
  final String taskId;
  final int? botId;
  final String updateType;
  final String dropReason;
  final int attempt;
  final int? queuedAt;
  final int? droppedAt;

  BotWebhookDeadLetterItem({
    required this.taskId,
    required this.botId,
    required this.updateType,
    required this.dropReason,
    required this.attempt,
    required this.queuedAt,
    required this.droppedAt,
  });

  factory BotWebhookDeadLetterItem.fromJson(Map<String, dynamic> json) {
    return BotWebhookDeadLetterItem(
      taskId: json['task_id'] as String? ?? '',
      botId: (json['bot_id'] as num?)?.toInt(),
      updateType: json['update_type'] as String? ?? '',
      dropReason: json['drop_reason'] as String? ?? '',
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      queuedAt: (json['queued_at'] as num?)?.toInt(),
      droppedAt: (json['dropped_at'] as num?)?.toInt(),
    );
  }
}

class BotWebhookDeadLetterPage {
  final List<BotWebhookDeadLetterItem> items;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;
  final int? nextOffset;
  final BotWebhookQueueStats? stats;

  BotWebhookDeadLetterPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
    this.nextOffset,
    this.stats,
  });

  factory BotWebhookDeadLetterPage.fromJson(Map<String, dynamic> json) {
    return BotWebhookDeadLetterPage(
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BotWebhookDeadLetterItem.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      hasMore: json['has_more'] == true,
      nextOffset: (json['next_offset'] as num?)?.toInt(),
      stats: json['stats'] is Map<String, dynamic>
          ? BotWebhookQueueStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }
}

class BotWebhookAlertItem {
  final String code;
  final String severity;
  final String message;
  final num value;
  final num threshold;

  BotWebhookAlertItem({
    required this.code,
    required this.severity,
    required this.message,
    required this.value,
    required this.threshold,
  });

  factory BotWebhookAlertItem.fromJson(Map<String, dynamic> json) {
    return BotWebhookAlertItem(
      code: json['code'] as String? ?? '',
      severity: json['severity'] as String? ?? 'warning',
      message: json['message'] as String? ?? 'Webhook alert',
      value: (json['value'] as num?) ?? 0,
      threshold: (json['threshold'] as num?) ?? 0,
    );
  }
}

class BotWebhookAlerts {
  final List<BotWebhookAlertItem> items;

  BotWebhookAlerts({required this.items});

  factory BotWebhookAlerts.fromJson(Map<String, dynamic> json) {
    return BotWebhookAlerts(
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BotWebhookAlertItem.fromJson)
          .toList(),
    );
  }
}

class BotWebhookQueueStats {
  final int queueDepth;
  final int delayedDepth;
  final int deadDepth;
  final int sentTotal;
  final int failedTotal;
  final int retriedTotal;
  final int droppedTotal;
  final int throttledTotal;
  final bool redisStub;

  BotWebhookQueueStats({
    required this.queueDepth,
    required this.delayedDepth,
    required this.deadDepth,
    required this.sentTotal,
    required this.failedTotal,
    required this.retriedTotal,
    required this.droppedTotal,
    required this.throttledTotal,
    required this.redisStub,
  });

  factory BotWebhookQueueStats.fromJson(Map<String, dynamic> json) {
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return BotWebhookQueueStats(
      queueDepth: asInt('queue_depth'),
      delayedDepth: asInt('delayed_depth'),
      deadDepth: asInt('dead_depth'),
      sentTotal: asInt('sent_total'),
      failedTotal: asInt('failed_total'),
      retriedTotal: asInt('retried_total'),
      droppedTotal: asInt('dropped_total'),
      throttledTotal: asInt('throttled_total'),
      redisStub: asInt('redis_stub') == 1,
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
