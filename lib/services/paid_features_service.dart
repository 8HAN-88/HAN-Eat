import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'auth_service.dart';
import 'payment_service.dart';

class PaidFeaturesService {
  static String get baseUrl => '${ApiService.baseUrl}/api/v1';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<StarsBalance> getBalance() async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/stars/balance'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarsBalance.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_errorMessage(response, 'Не удалось загрузить баланс'));
  }

  static Future<List<StarPackage>> getStarPackages() async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/stars/packages'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final packages = data['packages'] as List<dynamic>? ?? const [];
      return packages
          .map((e) => StarPackage.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Не удалось загрузить пакеты звёзд'));
  }

  static Future<CheckoutSessionResponse> createStarsCheckout(String packageId) {
    return PaymentService.createStarsCheckout(packageId: packageId);
  }

  static Future<PurchaseContentResult> purchaseContent(int postId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/content/$postId/purchase'),
      headers: await _headers(),
      body: jsonEncode({
        'idempotency_key':
            'flutter:post:$postId:${DateTime.now().millisecondsSinceEpoch}',
      }),
    );
    if (response.statusCode == 200) {
      return PurchaseContentResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(_errorMessage(response, 'Не удалось купить контент'));
  }

  static Future<int> donate({
    required int recipientId,
    required int amountStars,
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/stars/donate'),
      headers: await _headers(),
      body: jsonEncode({
        'recipient_id': recipientId,
        'amount_stars': amountStars,
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['balance'] as int? ?? 0;
    }
    throw Exception(_errorMessage(response, 'Не удалось отправить донат'));
  }

  static Future<void> subscribeChannel(
    int channelId, {
    int months = 1,
    bool autoRenew = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/channels/$channelId/subscribe'),
      headers: await _headers(),
      body: jsonEncode({'months': months, 'auto_renew': autoRenew}),
    );
    if (response.statusCode == 200) return;
    throw Exception(_errorMessage(response, 'Не удалось оформить подписку'));
  }

  static Future<void> boostPost({
    required int postId,
    required int amountStars,
    int durationDays = 7,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/posts/$postId/boost'),
      headers: await _headers(),
      body: jsonEncode({
        'amount_stars': amountStars,
        'duration_days': durationDays,
      }),
    );
    if (response.statusCode == 200) return;
    throw Exception(_errorMessage(response, 'Не удалось запустить буст'));
  }

  static Future<List<StarTransaction>> getTransactions({int limit = 30}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/stars/transactions?limit=$limit'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => StarTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Не удалось загрузить историю'));
  }

  static Future<CreatorPayoutRequest> requestCreatorPayout({
    required int amountStars,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/payouts/request'),
      headers: await _headers(),
      body: jsonEncode({
        'amount_stars': amountStars,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
    if (response.statusCode == 200) {
      return CreatorPayoutRequest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(_errorMessage(response, 'Не удалось запросить выплату'));
  }

  static Future<List<CreatorPayoutRequest>> getMyPayoutRequests({
    int limit = 30,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/payouts/me?limit=$limit'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => CreatorPayoutRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Не удалось загрузить выплаты'));
  }

  static Future<PurchaseMessageResult> purchaseMessage(int messageId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/messages/$messageId/purchase'),
      headers: await _headers(),
      body: jsonEncode({
        'idempotency_key':
            'flutter:msg:$messageId:${DateTime.now().millisecondsSinceEpoch}',
      }),
    );
    if (response.statusCode == 200) {
      return PurchaseMessageResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(_errorMessage(response, 'Не удалось открыть медиа'));
  }

  static Future<List<StarGift>> getGifts() async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/gifts'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final gifts = data['gifts'] as List<dynamic>? ?? const [];
      return gifts
          .map((e) => StarGift.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Не удалось загрузить подарки'));
  }

  static Future<SendGiftResult> sendGift({
    required int giftId,
    required int conversationId,
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/$giftId/send'),
      headers: await _headers(),
      body: jsonEncode({
        'conversation_id': conversationId,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      }),
    );
    if (response.statusCode == 200) {
      return SendGiftResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(_errorMessage(response, 'Не удалось отправить подарок'));
  }

  static String _errorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is Map && detail['message'] is String) {
        return detail['message'] as String;
      }
    } catch (_) {}
    return fallback;
  }
}

class StarsBalance {
  const StarsBalance({
    required this.balance,
    required this.creatorAvailableStars,
    required this.creatorPendingStars,
  });

  final int balance;
  final int creatorAvailableStars;
  final int creatorPendingStars;

  factory StarsBalance.fromJson(Map<String, dynamic> json) => StarsBalance(
        balance: json['balance'] as int? ?? 0,
        creatorAvailableStars: json['creator_available_stars'] as int? ?? 0,
        creatorPendingStars: json['creator_pending_stars'] as int? ?? 0,
      );
}

class StarPackage {
  const StarPackage({
    required this.id,
    required this.stars,
    required this.priceRub,
    required this.title,
  });

  final String id;
  final int stars;
  final int priceRub;
  final String title;

  factory StarPackage.fromJson(Map<String, dynamic> json) => StarPackage(
        id: json['id'] as String,
        stars: json['stars'] as int? ?? 0,
        priceRub: json['price_rub'] as int? ?? 0,
        title: json['title'] as String? ?? '',
      );
}

class PurchaseContentResult {
  const PurchaseContentResult({
    required this.postId,
    required this.purchased,
    required this.amountStars,
    required this.balance,
  });

  final int postId;
  final bool purchased;
  final int amountStars;
  final int balance;

  factory PurchaseContentResult.fromJson(Map<String, dynamic> json) =>
      PurchaseContentResult(
        postId: json['post_id'] as int? ?? 0,
        purchased: json['purchased'] as bool? ?? false,
        amountStars: json['amount_stars'] as int? ?? 0,
        balance: json['balance'] as int? ?? 0,
      );
}

class StarTransaction {
  const StarTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.status,
    required this.createdAt,
    this.counterpartyUserId,
    this.referenceType,
    this.referenceId,
  });

  final int id;
  final int amount;
  final String type;
  final String status;
  final DateTime createdAt;
  final int? counterpartyUserId;
  final String? referenceType;
  final int? referenceId;

  factory StarTransaction.fromJson(Map<String, dynamic> json) => StarTransaction(
        id: json['id'] as int? ?? 0,
        amount: json['amount'] as int? ?? 0,
        type: json['type'] as String? ?? '',
        status: json['status'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        counterpartyUserId: json['counterparty_user_id'] as int?,
        referenceType: json['reference_type'] as String?,
        referenceId: json['reference_id'] as int?,
      );
}

class CreatorPayoutRequest {
  const CreatorPayoutRequest({
    required this.id,
    required this.creatorUserId,
    required this.amountStars,
    required this.amountRub,
    required this.status,
    this.note,
    this.createdAt,
  });

  final int id;
  final int creatorUserId;
  final int amountStars;
  final double amountRub;
  final String status;
  final String? note;
  final DateTime? createdAt;

  factory CreatorPayoutRequest.fromJson(Map<String, dynamic> json) =>
      CreatorPayoutRequest(
        id: json['id'] as int? ?? 0,
        creatorUserId: json['creator_user_id'] as int? ?? 0,
        amountStars: json['amount_stars'] as int? ?? 0,
        amountRub: (json['amount_rub'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'pending',
        note: json['note'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

class PurchaseMessageResult {
  const PurchaseMessageResult({
    required this.messageId,
    required this.purchased,
    required this.amountStars,
    required this.balance,
  });

  final int messageId;
  final bool purchased;
  final int amountStars;
  final int balance;

  factory PurchaseMessageResult.fromJson(Map<String, dynamic> json) =>
      PurchaseMessageResult(
        messageId: json['message_id'] as int? ?? 0,
        purchased: json['purchased'] as bool? ?? false,
        amountStars: json['amount_stars'] as int? ?? 0,
        balance: json['balance'] as int? ?? 0,
      );
}

class StarGift {
  const StarGift({
    required this.id,
    required this.slug,
    required this.title,
    required this.emoji,
    required this.stars,
  });

  final int id;
  final String slug;
  final String title;
  final String emoji;
  final int stars;

  factory StarGift.fromJson(Map<String, dynamic> json) => StarGift(
        id: json['id'] as int? ?? 0,
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '🎁',
        stars: json['stars'] as int? ?? 0,
      );
}

class SendGiftResult {
  const SendGiftResult({
    required this.messageId,
    required this.conversationId,
    required this.giftId,
    required this.stars,
    required this.balance,
  });

  final int messageId;
  final int conversationId;
  final int giftId;
  final int stars;
  final int balance;

  factory SendGiftResult.fromJson(Map<String, dynamic> json) => SendGiftResult(
        messageId: json['message_id'] as int? ?? 0,
        conversationId: json['conversation_id'] as int? ?? 0,
        giftId: json['gift_id'] as int? ?? 0,
        stars: json['stars'] as int? ?? 0,
        balance: json['balance'] as int? ?? 0,
      );
}
