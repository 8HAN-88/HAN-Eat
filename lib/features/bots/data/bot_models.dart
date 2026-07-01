// Модели для BotFather API

class BotCreateRequest {
  final String name;
  final String username;
  final String? description;
  final String? shortDescription;
  final List<BotCommandCreate> commands;

  BotCreateRequest({
    required this.name,
    required this.username,
    this.description,
    this.shortDescription,
    this.commands = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'username': username,
        if (description != null) 'description': description,
        if (shortDescription != null) 'short_description': shortDescription,
        'commands': commands.map((c) => c.toJson()).toList(),
      };
}

class BotCommandCreate {
  final String command;
  final String description;
  final String? responseText;
  final List<List<BotInlineButton>> inlineButtonRows;

  BotCommandCreate({
    required this.command,
    required this.description,
    this.responseText,
    this.inlineButtonRows = const [],
  });

  List<BotInlineButton> get inlineButtons =>
      inlineButtonRows.expand((row) => row).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'command': command,
        'description': description,
        if (responseText != null && responseText!.trim().isNotEmpty)
          'response_text': responseText!.trim(),
        if (inlineButtonRows.isNotEmpty)
          'inline_button_rows': inlineButtonRows
              .map((row) => row.map((e) => e.toJson()).toList())
              .toList(),
      };
}

class BotInlineButton {
  final String text;
  final String? callbackData;
  final String? url;
  final String? callbackText;

  const BotInlineButton({
    required this.text,
    this.callbackData,
    this.url,
    this.callbackText,
  });

  factory BotInlineButton.fromJson(Map<String, dynamic> json) => BotInlineButton(
        text: json['text'] as String? ?? '',
        callbackData: json['callback_data'] as String?,
        url: json['url'] as String?,
        callbackText: json['callback_text'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        if (callbackData != null && callbackData!.trim().isNotEmpty)
          'callback_data': callbackData!.trim(),
        if (url != null && url!.trim().isNotEmpty) 'url': url!.trim(),
        if (callbackText != null && callbackText!.trim().isNotEmpty)
          'callback_text': callbackText!.trim(),
      };
}

class BotResponse {
  final int id;
  final String name;
  final String username;
  final String botToken;
  final String? description;
  final String? shortDescription;
  final String? avatarUrl;
  final String? webhookUrl;
  final bool webhookEnabled;
  final String? webhookLastError;
  final DateTime? webhookLastOkAt;

  BotResponse({
    required this.id,
    required this.name,
    required this.username,
    required this.botToken,
    this.description,
    this.shortDescription,
    this.avatarUrl,
    this.webhookUrl,
    this.webhookEnabled = false,
    this.webhookLastError,
    this.webhookLastOkAt,
  });

  factory BotResponse.fromJson(Map<String, dynamic> json) => BotResponse(
        id: json['id'] as int,
        name: json['name'] as String,
        username: json['username'] as String,
        botToken: json['bot_token'] as String,
        description: json['description'] as String?,
        shortDescription: json['short_description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        webhookUrl: json['webhook_url'] as String?,
        webhookEnabled: json['webhook_enabled'] as bool? ?? false,
        webhookLastError: json['webhook_last_error'] as String?,
        webhookLastOkAt: json['webhook_last_ok_at'] is String
            ? DateTime.tryParse(json['webhook_last_ok_at'] as String)
            : null,
      );
}

class BotListItem {
  final int id;
  final String name;
  final String username;
  final String? description;
  final String? shortDescription;
  final String? avatarUrl;

  BotListItem({
    required this.id,
    required this.name,
    required this.username,
    this.description,
    this.shortDescription,
    this.avatarUrl,
  });

  factory BotListItem.fromJson(Map<String, dynamic> json) => BotListItem(
        id: json['id'] as int,
        name: json['name'] as String,
        username: json['username'] as String,
        description: json['description'] as String?,
        shortDescription: json['short_description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class BotAnalyticsDay {
  final DateTime date;
  final int count;
  const BotAnalyticsDay({required this.date, required this.count});

  factory BotAnalyticsDay.fromJson(Map<String, dynamic> json) => BotAnalyticsDay(
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

class BotAnalyticsTopItem {
  final String key;
  final int count;
  const BotAnalyticsTopItem({required this.key, required this.count});
}

class BotWebhookErrorItem {
  final String error;
  final int count;
  const BotWebhookErrorItem({required this.error, required this.count});
}

class BotWebhookDeliveryHealth {
  final int sent;
  final int failed;
  final int attempted;
  final double successRatePercent;
  final DateTime? lastOkAt;
  final String? lastError;
  final List<BotWebhookErrorItem> topErrors;

  const BotWebhookDeliveryHealth({
    required this.sent,
    required this.failed,
    required this.attempted,
    required this.successRatePercent,
    this.lastOkAt,
    this.lastError,
    this.topErrors = const [],
  });

  factory BotWebhookDeliveryHealth.fromJson(Map<String, dynamic> json) {
    return BotWebhookDeliveryHealth(
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      attempted: (json['attempted'] as num?)?.toInt() ?? 0,
      successRatePercent:
          (json['success_rate_percent'] as num?)?.toDouble() ?? 0.0,
      lastOkAt: json['last_ok_at'] is String
          ? DateTime.tryParse(json['last_ok_at'] as String)
          : null,
      lastError: json['last_error'] as String?,
      topErrors: ((json['top_errors'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => BotWebhookErrorItem(
              error: (e['error'] as String? ?? '').trim(),
              count: (e['count'] as num?)?.toInt() ?? 0,
            ),
          )
          .where((e) => e.error.isNotEmpty)
          .toList(),
    );
  }
}

class BotWebhookAttempt {
  final int id;
  final String status;
  final String eventType;
  final String? updateType;
  final String? deliveryId;
  final int attemptsUsed;
  final String? error;
  final DateTime? createdAt;

  const BotWebhookAttempt({
    required this.id,
    required this.status,
    required this.eventType,
    this.updateType,
    this.deliveryId,
    this.attemptsUsed = 0,
    this.error,
    this.createdAt,
  });

  factory BotWebhookAttempt.fromJson(Map<String, dynamic> json) {
    return BotWebhookAttempt(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String? ?? 'unknown').trim(),
      eventType: (json['event_type'] as String? ?? '').trim(),
      updateType: (json['update_type'] as String?)?.trim(),
      deliveryId: (json['delivery_id'] as String?)?.trim(),
      attemptsUsed: (json['attempts_used'] as num?)?.toInt() ?? 0,
      error: (json['error'] as String?)?.trim(),
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

class BotAnalyticsResponse {
  final int botId;
  final int periodDays;
  final int commandUses;
  final int callbackClicks;
  final int uniqueUsers;
  final double callbackCtrPercent;
  final List<BotAnalyticsDay> byDay;
  final List<BotAnalyticsTopItem> topCommands;
  final List<BotAnalyticsTopItem> topCallbacks;
  final BotWebhookDeliveryHealth webhookDelivery;

  const BotAnalyticsResponse({
    required this.botId,
    required this.periodDays,
    required this.commandUses,
    required this.callbackClicks,
    required this.uniqueUsers,
    required this.callbackCtrPercent,
    required this.byDay,
    required this.topCommands,
    required this.topCallbacks,
    required this.webhookDelivery,
  });

  factory BotAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    List<BotAnalyticsTopItem> parseTop(
      List<dynamic>? raw,
      String field,
    ) {
      final out = <BotAnalyticsTopItem>[];
      for (final item in raw ?? const []) {
        if (item is! Map<String, dynamic>) continue;
        final key = (item[field] as String? ?? '').trim();
        if (key.isEmpty) continue;
        out.add(BotAnalyticsTopItem(
          key: key,
          count: (item['count'] as num?)?.toInt() ?? 0,
        ));
      }
      return out;
    }

    return BotAnalyticsResponse(
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      periodDays: (json['period_days'] as num?)?.toInt() ?? 30,
      commandUses: (json['command_uses'] as num?)?.toInt() ?? 0,
      callbackClicks: (json['callback_clicks'] as num?)?.toInt() ?? 0,
      uniqueUsers: (json['unique_users'] as num?)?.toInt() ?? 0,
      callbackCtrPercent:
          (json['callback_ctr_percent'] as num?)?.toDouble() ?? 0.0,
      byDay: ((json['by_day'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BotAnalyticsDay.fromJson)
          .toList(),
      topCommands: parseTop(json['top_commands'] as List?, 'command'),
      topCallbacks: parseTop(json['top_callbacks'] as List?, 'data'),
      webhookDelivery: BotWebhookDeliveryHealth.fromJson(
        (json['webhook_delivery'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
