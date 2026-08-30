import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'auth_service.dart';

class FlexSubscriptionApi {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1/flex';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Never _throw(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  static Future<FlexMe> me() async {
    final response = await http.get(Uri.parse('$baseUrl/me'), headers: await _headers());
    if (response.statusCode == 200) {
      return FlexMe.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throw(response, 'Не удалось загрузить подписку');
  }

  static Future<FlexShop> shop() async {
    final response = await http.get(Uri.parse('$baseUrl/shop'), headers: await _headers());
    if (response.statusCode == 200) {
      return FlexShop.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throw(response, 'Не удалось загрузить магазин функций');
  }

  static Future<FlexPreview> preview(int level) async {
    final response = await http.post(
      Uri.parse('$baseUrl/preview'),
      headers: await _headers(),
      body: jsonEncode({'level': level}),
    );
    if (response.statusCode == 200) {
      return FlexPreview.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throw(response, 'Не удалось построить превью');
  }

  static Future<FlexMe> saveLayout(List<FlexSlot> slots) async {
    final response = await http.post(
      Uri.parse('$baseUrl/layout'),
      headers: await _headers(),
      body: jsonEncode({
        'slots': [
          for (final s in slots) {'feature_id': s.featureId, 'level': s.level},
        ],
      }),
    );
    if (response.statusCode == 200) {
      return FlexMe.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throw(response, 'Не удалось сохранить конфигурацию');
  }

  static Future<FlexMe> move({required int featureId, required int targetLevel}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/move'),
      headers: await _headers(),
      body: jsonEncode({'feature_id': featureId, 'target_level': targetLevel}),
    );
    if (response.statusCode == 200) {
      return FlexMe.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throw(response, 'Нельзя переместить функцию');
  }

  static Future<void> checkout(int level) async {
    final response = await http.post(
      Uri.parse('$baseUrl/checkout'),
      headers: await _headers(),
      body: jsonEncode({'level': level}),
    );
    if (response.statusCode != 200) {
      _throw(response, 'Не удалось создать оплату');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const ApiClientException(message: 'Платёжная ссылка не получена');
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const ApiClientException(message: 'Не удалось открыть оплату');
    }
  }

  static Future<FlexAdminCatalog> adminCatalog() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/features'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return FlexAdminCatalog.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throw(response, 'Не удалось загрузить каталог');
  }

  static Future<void> adminSaveFeature(Map<String, dynamic> body, {int? id}) async {
    final uri = id == null
        ? Uri.parse('$baseUrl/admin/features')
        : Uri.parse('$baseUrl/admin/features/$id');
    final response = id == null
        ? await http.post(uri, headers: await _headers(), body: jsonEncode(body))
        : await http.patch(uri, headers: await _headers(), body: jsonEncode(body));
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throw(response, 'Не удалось сохранить функцию');
    }
  }
}

class FlexSlot {
  const FlexSlot({required this.featureId, required this.level});
  final int featureId;
  final int level;
}

class FlexFeature {
  const FlexFeature({
    required this.id,
    required this.slug,
    required this.title,
    required this.assignedLevel,
    required this.minLevel,
    required this.maxLevel,
    required this.featureType,
    required this.movable,
    required this.required,
    required this.unlocked,
    this.description,
    this.icon,
    this.blockKey,
    this.shopState,
  });

  final int id;
  final String slug;
  final String title;
  final String? description;
  final String? icon;
  final int assignedLevel;
  final int minLevel;
  final int maxLevel;
  final String featureType;
  final bool movable;
  final bool required;
  final bool unlocked;
  final String? blockKey;
  final String? shopState;

  bool canPlace(int level) {
    if (!movable || featureType == 'fixed') return false;
    if (level < minLevel || level > maxLevel) return false;
    return true;
  }

  factory FlexFeature.fromJson(Map<String, dynamic> json) => FlexFeature(
        id: json['id'] as int? ?? 0,
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        assignedLevel: json['assigned_level'] as int? ?? json['default_level'] as int? ?? 1,
        minLevel: json['min_level'] as int? ?? 1,
        maxLevel: json['max_level'] as int? ?? 79,
        featureType: json['feature_type'] as String? ?? 'movable',
        movable: json['movable'] as bool? ?? true,
        required: json['required'] as bool? ?? false,
        unlocked: json['unlocked'] as bool? ?? false,
        blockKey: json['block_key'] as String?,
        shopState: json['shop_state'] as String?,
      );
}

class FlexBlock {
  const FlexBlock({
    required this.key,
    required this.title,
    required this.minLevel,
    required this.maxLevel,
  });

  final String key;
  final String title;
  final int minLevel;
  final int maxLevel;

  factory FlexBlock.fromJson(Map<String, dynamic> json) => FlexBlock(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        minLevel: json['min_level'] as int? ?? 1,
        maxLevel: json['max_level'] as int? ?? 3,
      );
}

class FlexMe {
  const FlexMe({
    required this.currentLevel,
    required this.priceRub,
    required this.maxLevel,
    required this.active,
    required this.levels,
    required this.blocks,
    this.nextLevel,
    this.nextPriceRub,
    this.nextFeature,
    this.expiresAt,
  });

  final int currentLevel;
  final int priceRub;
  final int maxLevel;
  final bool active;
  final int? nextLevel;
  final int? nextPriceRub;
  final FlexFeature? nextFeature;
  final String? expiresAt;
  final List<FlexFeature> levels;
  final List<FlexBlock> blocks;

  factory FlexMe.fromJson(Map<String, dynamic> json) => FlexMe(
        currentLevel: json['current_level'] as int? ?? 0,
        priceRub: json['price_rub'] as int? ?? 0,
        maxLevel: json['max_level'] as int? ?? 79,
        active: json['active'] as bool? ?? false,
        nextLevel: json['next_level'] as int?,
        nextPriceRub: json['next_price_rub'] as int?,
        nextFeature: json['next_feature'] is Map<String, dynamic>
            ? FlexFeature.fromJson(json['next_feature'] as Map<String, dynamic>)
            : null,
        expiresAt: json['expires_at'] as String?,
        levels: [
          for (final raw in (json['levels'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        blocks: [
          for (final raw in (json['blocks'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexBlock.fromJson(raw),
        ],
      );
}

class FlexShop {
  const FlexShop({required this.currentLevel, required this.features});
  final int currentLevel;
  final List<FlexFeature> features;

  factory FlexShop.fromJson(Map<String, dynamic> json) => FlexShop(
        currentLevel: json['current_level'] as int? ?? 0,
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
      );
}

class FlexPreview {
  const FlexPreview({
    required this.level,
    required this.priceRub,
    required this.features,
    required this.needsConfirm,
    required this.deltaRub,
    this.nextLevel,
    this.nextPriceRub,
    this.nextFeature,
    this.nextFeatures = const [],
    this.disabled = const [],
    this.added = const [],
  });

  final int level;
  final int priceRub;
  final int? nextLevel;
  final int? nextPriceRub;
  final FlexFeature? nextFeature;
  final List<FlexFeature> nextFeatures;
  final List<FlexFeature> features;
  final List<FlexFeature> disabled;
  final List<FlexFeature> added;
  final bool needsConfirm;
  final int deltaRub;

  factory FlexPreview.fromJson(Map<String, dynamic> json) => FlexPreview(
        level: json['level'] as int? ?? 1,
        priceRub: json['price_rub'] as int? ?? 0,
        nextLevel: json['next_level'] as int?,
        nextPriceRub: json['next_price_rub'] as int?,
        nextFeature: json['next_feature'] is Map<String, dynamic>
            ? FlexFeature.fromJson(json['next_feature'] as Map<String, dynamic>)
            : null,
        nextFeatures: [
          for (final raw in (json['next_features'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        disabled: [
          for (final raw in (json['disabled'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        added: [
          for (final raw in (json['added'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        needsConfirm: json['needs_confirm'] as bool? ?? false,
        deltaRub: json['delta_rub'] as int? ?? 0,
      );
}

class FlexAdminCatalog {
  const FlexAdminCatalog({required this.features, required this.blocks});
  final List<FlexFeature> features;
  final List<FlexBlock> blocks;

  factory FlexAdminCatalog.fromJson(Map<String, dynamic> json) => FlexAdminCatalog(
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        blocks: [
          for (final raw in (json['blocks'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexBlock.fromJson(raw),
        ],
      );
}
