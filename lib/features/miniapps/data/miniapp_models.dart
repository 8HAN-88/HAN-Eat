class MiniAppItem {
  const MiniAppItem({
    required this.id,
    required this.botId,
    required this.botUsername,
    required this.botName,
    required this.name,
    required this.shortName,
    this.description,
    required this.url,
    this.iconUrl,
    this.isBuiltin = false,
    this.isOfficial = false,
    this.isActive = true,
    this.moderationStatus = 'pending',
    this.moderationNote,
    this.urlHost,
    this.urlScheme,
    this.urlRiskLevel = 'low',
    this.urlRiskReasons = const [],
    this.iconUrlHost,
    this.iconUrlRiskLevel,
    this.iconUrlRiskReasons = const [],
    this.isInstalled = false,
    this.isOwner = false,
  });

  final int id;
  final int botId;
  final String botUsername;
  final String botName;
  final String name;
  final String shortName;
  final String? description;
  final String url;
  final String? iconUrl;
  final bool isBuiltin;
  final bool isOfficial;
  final bool isActive;
  final String moderationStatus;
  final String? moderationNote;
  final String? urlHost;
  final String? urlScheme;
  final String urlRiskLevel;
  final List<String> urlRiskReasons;
  final String? iconUrlHost;
  final String? iconUrlRiskLevel;
  final List<String> iconUrlRiskReasons;
  final bool isInstalled;
  final bool isOwner;

  bool get isApproved => moderationStatus == 'approved';
  bool get isRejected => moderationStatus == 'rejected';

  factory MiniAppItem.fromJson(Map<String, dynamic> json) {
    return MiniAppItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      botUsername: json['bot_username'] as String? ?? '',
      botName: json['bot_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      shortName: json['short_name'] as String? ?? '',
      description: json['description'] as String?,
      url: json['url'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      isBuiltin: json['is_builtin'] as bool? ?? false,
      isOfficial: json['is_official'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      moderationStatus: json['moderation_status'] as String? ?? 'pending',
      moderationNote: json['moderation_note'] as String?,
      urlHost: json['url_host'] as String?,
      urlScheme: json['url_scheme'] as String?,
      urlRiskLevel: json['url_risk_level'] as String? ?? 'low',
      urlRiskReasons: ((json['url_risk_reasons'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
      iconUrlHost: json['icon_url_host'] as String?,
      iconUrlRiskLevel: json['icon_url_risk_level'] as String?,
      iconUrlRiskReasons: ((json['icon_url_risk_reasons'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
      isInstalled: json['is_installed'] as bool? ?? false,
      isOwner: json['is_owner'] as bool? ?? false,
    );
  }
}

class MiniAppCreateRequest {
  const MiniAppCreateRequest({
    required this.botId,
    required this.name,
    required this.shortName,
    required this.url,
    this.description,
    this.iconUrl,
  });

  final int botId;
  final String name;
  final String shortName;
  final String url;
  final String? description;
  final String? iconUrl;

  Map<String, dynamic> toJson() => {
        'bot_id': botId,
        'name': name,
        'short_name': shortName,
        'url': url,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (iconUrl != null && iconUrl!.isNotEmpty) 'icon_url': iconUrl,
      };
}

class MiniAppUpdateRequest {
  const MiniAppUpdateRequest({
    this.name,
    this.description,
    this.url,
    this.iconUrl,
    this.isActive,
  });

  final String? name;
  final String? description;
  final String? url;
  final String? iconUrl;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (iconUrl != null) 'icon_url': iconUrl,
        if (isActive != null) 'is_active': isActive,
      };
}

class MiniAppLaunchContext {
  const MiniAppLaunchContext({
    required this.miniappId,
    required this.url,
    required this.initData,
    required this.initDataUnsafe,
  });

  final int miniappId;
  final String url;
  final String initData;
  final Map<String, dynamic> initDataUnsafe;

  factory MiniAppLaunchContext.fromJson(Map<String, dynamic> json) {
    return MiniAppLaunchContext(
      miniappId: (json['miniapp_id'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? '',
      initData: json['init_data'] as String? ?? '{}',
      initDataUnsafe:
          (json['init_data_unsafe'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
