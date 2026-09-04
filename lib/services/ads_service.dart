import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'api_service.dart';
import 'auth_service.dart';

class AdsService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Never _throwForResponse(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  static Map<String, dynamic> _jsonBody(AdCampaignDraft draft) {
    return {
      if (draft.name != null) 'name': draft.name,
      if (draft.surfaces != null) 'surfaces': draft.surfaces,
      if (draft.destinationType != null)
        'destination_type': draft.destinationType,
      if (draft.destinationUrl != null)
        'destination_url': draft.destinationUrl,
      if (draft.destinationChannelId != null)
        'destination_channel_id': draft.destinationChannelId,
      if (draft.destinationPostId != null)
        'destination_post_id': draft.destinationPostId,
      if (draft.startsAt != null) 'starts_at': draft.startsAt,
      if (draft.endsAt != null) 'ends_at': draft.endsAt,
      if (draft.dailyCap != null) 'daily_cap': draft.dailyCap,
      if (draft.creative != null) 'creative': draft.creative!.toJson(),
    };
  }

  static Future<List<AdCampaign>> listMine() async {
    final response = await http.get(
      Uri.parse('$baseUrl/ads/campaigns'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['campaigns'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AdCampaign.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить кампании');
  }

  static Future<AdCampaign> getCampaign(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/ads/campaigns/$id'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось загрузить кампанию');
  }

  static Future<AdCampaign> create(AdCampaignDraft draft) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/campaigns'),
      headers: await _headers(),
      body: jsonEncode(_jsonBody(draft)),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось создать кампанию');
  }

  static Future<AdCampaign> update(int id, AdCampaignDraft draft) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/ads/campaigns/$id'),
      headers: await _headers(),
      body: jsonEncode(_jsonBody(draft)),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось сохранить кампанию');
  }

  static Future<AdCampaign> submit(int id, [AdCampaignDraft? draft]) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/campaigns/$id/submit'),
      headers: await _headers(),
      body: jsonEncode(draft == null ? <String, dynamic>{} : _jsonBody(draft)),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отправить на модерацию');
  }

  static Future<AdCampaign> pause(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/campaigns/$id/pause'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось поставить на паузу');
  }

  static Future<AdCampaign> resume(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/campaigns/$id/resume'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось возобновить кампанию');
  }

  static Future<AdCampaign> archive(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/campaigns/$id/archive'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось архивировать кампанию');
  }

  static Future<List<AdCampaign>> listReview({
    String status = 'pending_review',
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/ads/review').replace(
        queryParameters: {'status': status},
      ),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['campaigns'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AdCampaign.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить очередь рекламы');
  }

  static Future<AdCampaign> approve(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/review/$id/approve'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось одобрить кампанию');
  }

  static Future<AdCampaign> reject(int id, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ads/review/$id/reject'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode == 200) {
      return AdCampaign.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отклонить кампанию');
  }
}

class AdCreativeDraft {
  const AdCreativeDraft({
    this.title,
    this.body,
    this.ctaLabel,
    this.imageUrl,
    this.videoUrl,
    this.advertiserName,
  });

  final String? title;
  final String? body;
  final String? ctaLabel;
  final String? imageUrl;
  final String? videoUrl;
  final String? advertiserName;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        if (ctaLabel != null) 'cta_label': ctaLabel,
        if (imageUrl != null) 'image_url': imageUrl,
        if (videoUrl != null) 'video_url': videoUrl,
        if (advertiserName != null) 'advertiser_name': advertiserName,
      };
}

class AdCampaignDraft {
  const AdCampaignDraft({
    this.name,
    this.surfaces,
    this.destinationType,
    this.destinationUrl,
    this.destinationChannelId,
    this.destinationPostId,
    this.startsAt,
    this.endsAt,
    this.dailyCap,
    this.creative,
  });

  final String? name;
  final List<String>? surfaces;
  final String? destinationType;
  final String? destinationUrl;
  final int? destinationChannelId;
  final int? destinationPostId;
  final String? startsAt;
  final String? endsAt;
  final int? dailyCap;
  final AdCreativeDraft? creative;
}

class AdCreative {
  const AdCreative({
    this.id,
    required this.title,
    required this.body,
    required this.ctaLabel,
    this.imageUrl,
    this.videoUrl,
    this.advertiserName,
  });

  final int? id;
  final String title;
  final String body;
  final String ctaLabel;
  final String? imageUrl;
  final String? videoUrl;
  final String? advertiserName;

  factory AdCreative.fromJson(Map<String, dynamic> json) => AdCreative(
        id: (json['id'] as num?)?.toInt(),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        ctaLabel: json['cta_label'] as String? ?? 'Подробнее',
        imageUrl: json['image_url'] as String?,
        videoUrl: json['video_url'] as String?,
        advertiserName: json['advertiser_name'] as String?,
      );
}

class AdAdvertiser {
  const AdAdvertiser({
    required this.id,
    this.name,
    this.username,
  });

  final int id;
  final String? name;
  final String? username;

  factory AdAdvertiser.fromJson(Map<String, dynamic> json) => AdAdvertiser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String?,
        username: json['username'] as String?,
      );
}

class AdCampaign {
  const AdCampaign({
    required this.id,
    required this.advertiserId,
    required this.name,
    required this.status,
    required this.isLive,
    required this.surfaces,
    required this.destinationType,
    this.destinationUrl,
    this.destinationChannelId,
    this.destinationPostId,
    this.startsAt,
    this.endsAt,
    this.dailyCap,
    this.rejectionReason,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
    required this.creative,
    this.advertiser,
  });

  final int id;
  final int advertiserId;
  final String name;
  final String status;
  final bool isLive;
  final List<String> surfaces;
  final String destinationType;
  final String? destinationUrl;
  final int? destinationChannelId;
  final int? destinationPostId;
  final String? startsAt;
  final String? endsAt;
  final int? dailyCap;
  final String? rejectionReason;
  final String? reviewedAt;
  final String? createdAt;
  final String? updatedAt;
  final AdCreative creative;
  final AdAdvertiser? advertiser;

  bool get isEditable => status == 'draft' || status == 'rejected';
  bool get canSubmit => isEditable;
  bool get canPause => status == 'approved';
  bool get canResume => status == 'paused';
  bool get canArchive => status != 'pending_review' && status != 'archived';

  String get statusLabel => switch (status) {
        'draft' => 'Черновик',
        'pending_review' => 'На модерации',
        'approved' => isLive ? 'В эфире' : 'Одобрена',
        'rejected' => 'Отклонена',
        'paused' => 'Пауза',
        'archived' => 'Архив',
        _ => status,
      };

  String get surfacesLabel {
    if (surfaces.isEmpty) return 'Площадки не выбраны';
    return surfaces.map(adSurfaceLabel).join(' · ');
  }

  factory AdCampaign.fromJson(Map<String, dynamic> json) {
    return AdCampaign(
      id: (json['id'] as num?)?.toInt() ?? 0,
      advertiserId: (json['advertiser_id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Кампания',
      status: json['status'] as String? ?? 'draft',
      isLive: json['is_live'] as bool? ?? false,
      surfaces: (json['surfaces'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      destinationType: json['destination_type'] as String? ?? 'url',
      destinationUrl: json['destination_url'] as String?,
      destinationChannelId: (json['destination_channel_id'] as num?)?.toInt(),
      destinationPostId: (json['destination_post_id'] as num?)?.toInt(),
      startsAt: json['starts_at'] as String?,
      endsAt: json['ends_at'] as String?,
      dailyCap: (json['daily_cap'] as num?)?.toInt(),
      rejectionReason: json['rejection_reason'] as String?,
      reviewedAt: json['reviewed_at'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      creative: AdCreative.fromJson(
        json['creative'] as Map<String, dynamic>? ?? const {},
      ),
      advertiser: json['advertiser'] is Map
          ? AdAdvertiser.fromJson(
              Map<String, dynamic>.from(json['advertiser'] as Map),
            )
          : null,
    );
  }
}

String adSurfaceLabel(String surface) {
  return switch (surface) {
    'feed' => 'Лента',
    'reels' => 'Рилсы',
    'channel' => 'Каналы',
    _ => surface,
  };
}
