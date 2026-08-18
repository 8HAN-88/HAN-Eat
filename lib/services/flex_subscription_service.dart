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

  static Future<FlexPreview> preview(int level, {String plan = 'monthly'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/preview'),
      headers: await _headers(),
      body: jsonEncode({'level': level, 'plan': plan}),
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

  static Future<FlexCheckoutResult> giftCheckout({
    required int recipientUserId,
    required int level,
    String plan = 'monthly',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/gift/checkout'),
      headers: await _headers(),
      body: jsonEncode({
        'recipient_user_id': recipientUserId,
        'level': level,
        'plan': plan,
      }),
    );
    if (response.statusCode != 200) {
      _throw(response, 'Не удалось создать подарок');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = FlexCheckoutResult.fromJson(data);
    final url = result.url;
    if (url == null || url.isEmpty) {
      throw const ApiClientException(message: 'Платёжная ссылка не получена');
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const ApiClientException(message: 'Не удалось открыть оплату');
    }
    return result;
  }

  static Future<Map<String, dynamic>> adminStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/stats'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _throw(response, 'Не удалось загрузить статистику');
  }

  static Future<FlexCheckoutResult> checkout(int level, {String plan = 'monthly'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/checkout'),
      headers: await _headers(),
      body: jsonEncode({'level': level, 'plan': plan}),
    );
    if (response.statusCode != 200) {
      _throw(response, 'Не удалось создать оплату');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = FlexCheckoutResult.fromJson(data);
    if (result.scheduled || result.unchanged) {
      return result;
    }
    final url = result.url;
    if (url == null || url.isEmpty) {
      throw const ApiClientException(message: 'Платёжная ссылка не получена');
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const ApiClientException(message: 'Не удалось открыть оплату');
    }
    return result;
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

class FlexCheckoutResult {
  const FlexCheckoutResult({
    this.url,
    this.scheduled = false,
    this.unchanged = false,
    this.pendingLevel,
    this.pendingPlan,
    this.appliesAt,
    this.kind,
    this.amount,
    this.plan,
  });

  final String? url;
  final bool scheduled;
  final bool unchanged;
  final int? pendingLevel;
  final String? pendingPlan;
  final String? appliesAt;
  final String? kind;
  final double? amount;
  final String? plan;

  factory FlexCheckoutResult.fromJson(Map<String, dynamic> json) => FlexCheckoutResult(
        url: json['url'] as String?,
        scheduled: json['scheduled'] == true,
        unchanged: json['unchanged'] == true,
        pendingLevel: json['pending_level'] as int?,
        pendingPlan: json['pending_plan'] as String?,
        appliesAt: json['applies_at'] as String?,
        kind: json['kind'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        plan: json['plan'] as String?,
      );
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

  bool get isFixed => !movable || featureType == 'fixed';

  bool canPlace(int level) {
    if (isFixed) return false;
    if (level < minLevel || level > maxLevel) return false;
    return true;
  }

  /// Короткая подсказка для невалидного слота: «только 4–6».
  String get placementRule {
    if (isFixed) return 'закреплена на $assignedLevel';
    return 'только $minLevel–$maxLevel';
  }

  String get placementHint {
    if (isFixed) return 'Закреплена на уровне $assignedLevel';
    return 'Можно поставить только на $minLevel–$maxLevel';
  }

  factory FlexFeature.fromJson(Map<String, dynamic> json) => FlexFeature(
        id: json['id'] as int? ?? 0,
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        assignedLevel: json['assigned_level'] as int? ?? json['default_level'] as int? ?? 1,
        minLevel: json['min_level'] as int? ?? 1,
        maxLevel: json['max_level'] as int? ?? 32,
        featureType: json['feature_type'] as String? ?? 'movable',
        movable: json['movable'] as bool? ?? true,
        required: json['required'] as bool? ?? false,
        unlocked: json['unlocked'] as bool? ?? false,
        blockKey: json['block_key'] as String?,
        shopState: json['shop_state'] as String?,
      );
}

class FlexPreset {
  const FlexPreset({
    required this.key,
    required this.title,
    required this.level,
  });

  final String key;
  final String title;
  final int level;

  factory FlexPreset.fromJson(Map<String, dynamic> json) => FlexPreset(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        level: json['level'] as int? ?? 1,
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
    this.presets = const [],
    this.basePriceRub = 39,
    this.stepPriceRub = 10,
    this.nextLevel,
    this.nextPriceRub,
    this.nextFeature,
    this.expiresAt,
    this.autoRenew = false,
    this.pendingLevel,
    this.pendingLevelAt,
    this.pendingPlan,
    this.plan = 'monthly',
    this.yearlyMonths = 10,
    this.yearlyPriceRub = 0,
  });

  final int currentLevel;
  final int priceRub;
  final int maxLevel;
  final bool active;
  final int? nextLevel;
  final int? nextPriceRub;
  final FlexFeature? nextFeature;
  final String? expiresAt;
  final bool autoRenew;
  final int? pendingLevel;
  final String? pendingLevelAt;
  final String? pendingPlan;
  final String plan;
  final int yearlyMonths;
  final int yearlyPriceRub;
  final List<FlexFeature> levels;
  final List<FlexBlock> blocks;
  final List<FlexPreset> presets;
  final int basePriceRub;
  final int stepPriceRub;

  bool get isYearly => plan == 'yearly';

  int priceForLevel(int level) {
    final n = level < 1 ? 1 : (level > maxLevel ? maxLevel : level);
    return basePriceRub + (n - 1) * stepPriceRub;
  }

  int priceForPlan(int level, [String? selected]) {
    final monthly = priceForLevel(level);
    if ((selected ?? plan) == 'yearly') return monthly * yearlyMonths;
    return monthly;
  }

  String periodLabel([String? selected]) =>
      (selected ?? plan) == 'yearly' ? 'год' : 'месяц';

  FlexFeature? featureAt(int level) {
    for (final item in levels) {
      if (item.assignedLevel == level) return item;
    }
    return null;
  }

  FlexBlock? blockFor(int level) {
    for (final block in blocks) {
      if (level >= block.minLevel && level <= block.maxLevel) return block;
    }
    return null;
  }

  factory FlexMe.fromJson(Map<String, dynamic> json) => FlexMe(
        currentLevel: json['current_level'] as int? ?? 0,
        priceRub: json['price_rub'] as int? ?? 0,
        maxLevel: json['max_level'] as int? ?? 32,
        active: json['active'] as bool? ?? false,
        basePriceRub: json['base_price_rub'] as int? ?? 39,
        stepPriceRub: json['step_price_rub'] as int? ?? 10,
        nextLevel: json['next_level'] as int?,
        nextPriceRub: json['next_price_rub'] as int?,
        nextFeature: json['next_feature'] is Map<String, dynamic>
            ? FlexFeature.fromJson(json['next_feature'] as Map<String, dynamic>)
            : null,
        expiresAt: json['expires_at'] as String?,
        autoRenew: json['auto_renew'] as bool? ?? false,
        pendingLevel: json['pending_level'] as int?,
        pendingLevelAt: json['pending_level_at'] as String?,
        pendingPlan: json['pending_plan'] as String?,
        plan: json['plan'] as String? ?? 'monthly',
        yearlyMonths: json['yearly_months'] as int? ?? 10,
        yearlyPriceRub: json['yearly_price_rub'] as int? ?? 0,
        levels: [
          for (final raw in (json['levels'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexFeature.fromJson(raw),
        ],
        blocks: [
          for (final raw in (json['blocks'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexBlock.fromJson(raw),
        ],
        presets: [
          for (final raw in (json['presets'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) FlexPreset.fromJson(raw),
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
    this.disabled = const [],
    this.added = const [],
    this.kind = 'new',
    this.amountDue = 0,
    this.remainingDays = 0,
    this.needsPayment = true,
    this.appliesAt,
    this.plan = 'monthly',
    this.currentPlan = 'monthly',
    this.periodPriceRub = 0,
    this.pendingPlan,
  });

  final int level;
  final int priceRub;
  final int? nextLevel;
  final int? nextPriceRub;
  final FlexFeature? nextFeature;
  final List<FlexFeature> features;
  final List<FlexFeature> disabled;
  final List<FlexFeature> added;
  final bool needsConfirm;
  final int deltaRub;
  final String kind;
  final double amountDue;
  final int remainingDays;
  final bool needsPayment;
  final String? appliesAt;
  final String plan;
  final String currentPlan;
  final int periodPriceRub;
  final String? pendingPlan;

  bool get isYearly => plan == 'yearly';
  int get displayPrice => periodPriceRub > 0 ? periodPriceRub : priceRub;

  factory FlexPreview.fromJson(Map<String, dynamic> json) => FlexPreview(
        level: json['level'] as int? ?? 1,
        priceRub: json['price_rub'] as int? ?? 0,
        nextLevel: json['next_level'] as int?,
        nextPriceRub: json['next_price_rub'] as int?,
        nextFeature: json['next_feature'] is Map<String, dynamic>
            ? FlexFeature.fromJson(json['next_feature'] as Map<String, dynamic>)
            : null,
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
        deltaRub: (json['delta_rub'] as num?)?.toInt() ?? 0,
        kind: json['kind'] as String? ?? 'new',
        amountDue: (json['amount_due'] as num?)?.toDouble() ?? 0,
        remainingDays: json['remaining_days'] as int? ?? 0,
        needsPayment: json['needs_payment'] as bool? ?? true,
        appliesAt: json['applies_at'] as String?,
        plan: json['plan'] as String? ?? 'monthly',
        currentPlan: json['current_plan'] as String? ?? 'monthly',
        periodPriceRub: (json['period_price_rub'] as num?)?.toInt() ?? 0,
        pendingPlan: json['pending_plan'] as String?,
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
