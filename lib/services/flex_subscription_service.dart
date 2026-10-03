import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'auth_service.dart';

int _flexJsonInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

int? _flexJsonIntOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

Map<String, dynamic>? _flexJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

class FlexSubscriptionApi {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1/flex';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Войдите в аккаунт');
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
    final response =
        await http.get(Uri.parse('$baseUrl/me'), headers: await _headers());
    if (response.statusCode == 200) {
      return FlexMe.fromJson(
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
    }
    _throw(response, 'Не удалось загрузить подписку');
  }

  static Future<FlexShop> shop() async {
    final response =
        await http.get(Uri.parse('$baseUrl/shop'), headers: await _headers());
    if (response.statusCode == 200) {
      return FlexShop.fromJson(
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
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
      return FlexPreview.fromJson(
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
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
      return FlexMe.fromJson(
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
    }
    _throw(response, 'Не удалось сохранить конфигурацию');
  }

  static Future<FlexMe> move(
      {required int featureId, required int targetLevel}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/move'),
      headers: await _headers(),
      body: jsonEncode({'feature_id': featureId, 'target_level': targetLevel}),
    );
    if (response.statusCode == 200) {
      return FlexMe.fromJson(
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
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
        _flexJsonMap(jsonDecode(response.body)) ?? const {},
      );
    }
    _throw(response, 'Не удалось загрузить каталог');
  }

  static Future<void> adminSaveFeature(Map<String, dynamic> body,
      {int? id}) async {
    final uri = id == null
        ? Uri.parse('$baseUrl/admin/features')
        : Uri.parse('$baseUrl/admin/features/$id');
    final response = id == null
        ? await http.post(uri,
            headers: await _headers(), body: jsonEncode(body))
        : await http.patch(uri,
            headers: await _headers(), body: jsonEncode(body));
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
        id: _flexJsonInt(json['id'], 0),
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        assignedLevel: _flexJsonIntOrNull(json['assigned_level']) ??
            _flexJsonIntOrNull(json['default_level']) ??
            1,
        minLevel: _flexJsonInt(json['min_level'], 1),
        maxLevel: _flexJsonInt(json['max_level'], 79),
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
        minLevel: _flexJsonInt(json['min_level'], 1),
        maxLevel: _flexJsonInt(json['max_level'], 79),
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
    this.checkoutAvailable = true,
    this.legalConsentRequired = false,
    this.checkoutMessage,
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
  final bool checkoutAvailable;
  final bool legalConsentRequired;
  final String? checkoutMessage;

  bool get canCheckout => checkoutAvailable && !legalConsentRequired;

  factory FlexMe.fromJson(Map<String, dynamic> json) => FlexMe(
        currentLevel: _flexJsonInt(json['current_level'], 0),
        priceRub: _flexJsonInt(json['price_rub'], 0),
        maxLevel: _flexJsonInt(json['max_level'], 79),
        active: json['active'] as bool? ?? false,
        nextLevel: _flexJsonIntOrNull(json['next_level']),
        nextPriceRub: _flexJsonIntOrNull(json['next_price_rub']),
        nextFeature: _flexJsonMap(json['next_feature']) != null
            ? FlexFeature.fromJson(_flexJsonMap(json['next_feature'])!)
            : null,
        expiresAt: json['expires_at'] as String?,
        checkoutAvailable: json['checkout_available'] as bool? ?? true,
        legalConsentRequired: json['legal_consent_required'] as bool? ?? false,
        checkoutMessage: json['checkout_message'] as String?,
        levels: [
          for (final raw in (json['levels'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        blocks: [
          for (final raw in (json['blocks'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexBlock.fromJson(_flexJsonMap(raw)!),
        ],
      );
}

class FlexShop {
  const FlexShop({
    required this.currentLevel,
    required this.features,
    this.checkoutAvailable = true,
    this.legalConsentRequired = false,
    this.checkoutMessage,
  });
  final int currentLevel;
  final List<FlexFeature> features;
  final bool checkoutAvailable;
  final bool legalConsentRequired;
  final String? checkoutMessage;

  bool get canCheckout => checkoutAvailable && !legalConsentRequired;

  factory FlexShop.fromJson(Map<String, dynamic> json) => FlexShop(
        currentLevel: _flexJsonInt(json['current_level'], 0),
        checkoutAvailable: json['checkout_available'] as bool? ?? true,
        legalConsentRequired: json['legal_consent_required'] as bool? ?? false,
        checkoutMessage: json['checkout_message'] as String?,
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
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
        level: _flexJsonInt(json['level'], 1),
        priceRub: _flexJsonInt(json['price_rub'], 0),
        nextLevel: _flexJsonIntOrNull(json['next_level']),
        nextPriceRub: _flexJsonIntOrNull(json['next_price_rub']),
        nextFeature: _flexJsonMap(json['next_feature']) != null
            ? FlexFeature.fromJson(_flexJsonMap(json['next_feature'])!)
            : null,
        nextFeatures: [
          for (final raw
              in (json['next_features'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        disabled: [
          for (final raw in (json['disabled'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        added: [
          for (final raw in (json['added'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        needsConfirm: json['needs_confirm'] as bool? ?? false,
        deltaRub: _flexJsonInt(json['delta_rub'], 0),
      );
}

class FlexAdminCatalog {
  const FlexAdminCatalog({required this.features, required this.blocks});
  final List<FlexFeature> features;
  final List<FlexBlock> blocks;

  factory FlexAdminCatalog.fromJson(Map<String, dynamic> json) =>
      FlexAdminCatalog(
        features: [
          for (final raw in (json['features'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexFeature.fromJson(_flexJsonMap(raw)!),
        ],
        blocks: [
          for (final raw in (json['blocks'] as List<dynamic>? ?? const []))
            if (_flexJsonMap(raw) != null) FlexBlock.fromJson(_flexJsonMap(raw)!),
        ],
      );
}
