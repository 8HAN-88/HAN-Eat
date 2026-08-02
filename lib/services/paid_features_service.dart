import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
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
    _throwForResponse(response, 'Не удалось загрузить баланс');
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
    _throwForResponse(response, 'Не удалось загрузить пакеты звёзд');
  }

  static Future<CheckoutSessionResponse> createStarsCheckout(
    String packageId, {
    String? successUrl,
    String? cancelUrl,
  }) {
    return PaymentService.createStarsCheckout(
      packageId: packageId,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );
  }

  static Future<PurchaseContentResult> purchaseContent(int postId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/content/$postId/purchase'),
      headers: await _headers(),
      body: jsonEncode({
        'idempotency_key': 'flutter:post:$postId',
      }),
    );
    if (response.statusCode == 200) {
      return PurchaseContentResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось купить контент');
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
    _throwForResponse(response, 'Не удалось отправить донат');
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
    _throwForResponse(response, 'Не удалось оформить подписку');
  }

  static Future<ChannelSubscriptionInfo> getChannelSubscription(
    int channelId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/channels/$channelId/subscription'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return ChannelSubscriptionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось загрузить подписку');
  }

  static Future<ChannelSubscriptionInfo> updateChannelSubscription(
    int channelId, {
    required bool autoRenew,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/paid/channels/$channelId/subscription'),
      headers: await _headers(),
      body: jsonEncode({'auto_renew': autoRenew}),
    );
    if (response.statusCode == 200) {
      return ChannelSubscriptionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось обновить подписку');
  }

  static Future<ChannelSubscriptionInfo> cancelChannelSubscription(
    int channelId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/channels/$channelId/subscription/cancel'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return ChannelSubscriptionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отменить подписку');
  }

  static Future<List<PaidMessageExceptionUser>> listMessageExceptions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/message-exceptions'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map(
            (e) => PaidMessageExceptionUser.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить исключения');
  }

  static Future<PaidMessageExceptionUser> addMessageException(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/message-exceptions'),
      headers: await _headers(),
      body: jsonEncode({'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return PaidMessageExceptionUser.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось добавить исключение');
  }

  static Future<void> removeMessageException(int userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/paid/message-exceptions/$userId'),
      headers: await _headers(),
    );
    if (response.statusCode == 200 || response.statusCode == 204) return;
    _throwForResponse(response, 'Не удалось удалить исключение');
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
    _throwForResponse(response, 'Не удалось запустить буст');
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
    _throwForResponse(response, 'Не удалось загрузить историю');
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
    _throwForResponse(response, 'Не удалось запросить выплату');
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
    _throwForResponse(response, 'Не удалось загрузить выплаты');
  }

  static Future<PurchaseMessageResult> purchaseMessage(int messageId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/messages/$messageId/purchase'),
      headers: await _headers(),
      body: jsonEncode({
        'idempotency_key': 'flutter:msg:$messageId',
      }),
    );
    if (response.statusCode == 200) {
      return PurchaseMessageResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось открыть медиа');
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
    _throwForResponse(response, 'Не удалось загрузить подарки');
  }

  static Future<SendGiftResult> sendGift({
    required int giftId,
    required int conversationId,
    String? message,
    String? idempotencyKey,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/$giftId/send'),
      headers: await _headers(),
      body: jsonEncode({
        'conversation_id': conversationId,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotency_key': idempotencyKey,
      }),
    );
    if (response.statusCode == 200) {
      return SendGiftResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отправить подарок');
  }

  static Future<List<UserStarGift>> listMyGifts({
    bool includeConverted = false,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/paid/gifts/inventory?include_converted=$includeConverted',
      ),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final gifts = data['gifts'] as List<dynamic>? ?? const [];
      return gifts
          .map((e) => UserStarGift.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить подарки');
  }

  static Future<List<UserStarGift>> listUserGifts(int userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/users/$userId/gifts'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final gifts = data['gifts'] as List<dynamic>? ?? const [];
      return gifts
          .map((e) => UserStarGift.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить подарки профиля');
  }

  static Future<ConvertGiftResult> convertGift(int userGiftId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/inventory/$userGiftId/convert'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return ConvertGiftResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось конвертировать подарок');
  }

  static Future<UserStarGift> keepGift(int userGiftId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/inventory/$userGiftId/keep'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return UserStarGift.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось сохранить подарок');
  }

  static Future<UserStarGift> setGiftDisplayed(
    int userGiftId, {
    required bool displayed,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/paid/gifts/inventory/$userGiftId/display'),
      headers: await _headers(),
      body: jsonEncode({'displayed': displayed}),
    );
    if (response.statusCode == 200) {
      return UserStarGift.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось обновить отображение подарка');
  }

  static Future<ConvertGiftResult> upgradeGift(int userGiftId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/inventory/$userGiftId/upgrade'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return ConvertGiftResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось улучшить подарок');
  }

  static Future<UserStarGift> transferGift(
    int userGiftId, {
    required int toUserId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/gifts/inventory/$userGiftId/transfer'),
      headers: await _headers(),
      body: jsonEncode({'to_user_id': toUserId}),
    );
    if (response.statusCode == 200) {
      return UserStarGift.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось передать подарок');
  }

  static Future<List<StarGiveaway>> listChannelGiveaways(
    int channelId, {
    bool activeOnly = false,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/paid/channels/$channelId/giveaways?active_only=$activeOnly',
      ),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['giveaways'] as List<dynamic>? ?? const [];
      return items
          .map((e) => StarGiveaway.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwForResponse(response, 'Не удалось загрузить розыгрыши');
  }

  static Future<StarGiveaway> createChannelGiveaway(
    int channelId, {
    required int prizeStars,
    int winnersCount = 1,
    int durationHours = 24,
    String? title,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/channels/$channelId/giveaways'),
      headers: await _headers(),
      body: jsonEncode({
        'prize_stars': prizeStars,
        'winners_count': winnersCount,
        'duration_hours': durationHours,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return StarGiveaway.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось создать розыгрыш');
  }

  static Future<StarGiveaway> joinGiveaway(int giveawayId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/giveaways/$giveawayId/join'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarGiveaway.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось участвовать в розыгрыше');
  }

  static Future<StarGiveaway> cancelGiveaway(int giveawayId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/giveaways/$giveawayId/cancel'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarGiveaway.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отменить розыгрыш');
  }

  static Future<StarGiveaway> finalizeGiveaway(int giveawayId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/giveaways/$giveawayId/finalize'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarGiveaway.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось завершить розыгрыш');
  }

  static Future<StarInvoice> createBotInvoice(
    int botId, {
    required String title,
    required int amountStars,
    String? description,
    String? payload,
    int expiresInHours = 24,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/bots/$botId/invoices'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'amount_stars': amountStars,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (payload != null && payload.trim().isNotEmpty)
          'payload': payload.trim(),
        'expires_in_hours': expiresInHours,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return StarInvoice.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось создать счёт');
  }

  static Future<StarInvoice> getInvoice(int invoiceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/paid/invoices/$invoiceId'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarInvoice.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось загрузить счёт');
  }

  static Future<PayInvoiceResult> payInvoice(int invoiceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/invoices/$invoiceId/pay'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return PayInvoiceResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось оплатить счёт');
  }

  static Future<StarInvoice> cancelInvoice(int invoiceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paid/invoices/$invoiceId/cancel'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StarInvoice.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _throwForResponse(response, 'Не удалось отменить счёт');
  }

  static Never _throwForResponse(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
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
    this.isLimited = false,
    this.totalSupply,
    this.soldCount = 0,
    this.remaining,
    this.upgradeStars = 0,
    this.transferStars = 0,
  });

  final int id;
  final String slug;
  final String title;
  final String emoji;
  final int stars;
  final bool isLimited;
  final int? totalSupply;
  final int soldCount;
  final int? remaining;
  final int upgradeStars;
  final int transferStars;

  bool get isSoldOut =>
      isLimited && remaining != null && remaining! <= 0;

  factory StarGift.fromJson(Map<String, dynamic> json) => StarGift(
        id: json['id'] as int? ?? 0,
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '🎁',
        stars: json['stars'] as int? ?? 0,
        isLimited: json['is_limited'] as bool? ?? false,
        totalSupply: json['total_supply'] as int?,
        soldCount: json['sold_count'] as int? ?? 0,
        remaining: json['remaining'] as int?,
        upgradeStars: json['upgrade_stars'] as int? ?? 0,
        transferStars: json['transfer_stars'] as int? ?? 0,
      );
}

class SendGiftResult {
  const SendGiftResult({
    required this.messageId,
    required this.conversationId,
    required this.giftId,
    required this.stars,
    required this.balance,
    this.userGiftId,
  });

  final int messageId;
  final int conversationId;
  final int giftId;
  final int stars;
  final int balance;
  final int? userGiftId;

  factory SendGiftResult.fromJson(Map<String, dynamic> json) => SendGiftResult(
        messageId: json['message_id'] as int? ?? 0,
        conversationId: json['conversation_id'] as int? ?? 0,
        giftId: json['gift_id'] as int? ?? 0,
        stars: json['stars'] as int? ?? 0,
        balance: json['balance'] as int? ?? 0,
        userGiftId: json['user_gift_id'] as int?,
      );
}

class UserStarGift {
  const UserStarGift({
    required this.id,
    required this.ownerId,
    required this.stars,
    required this.slug,
    required this.title,
    required this.emoji,
    required this.status,
    this.senderId,
    this.giftId,
    this.messageId,
    this.note,
    this.isDisplayed = true,
    this.isCollectible = false,
    this.serial,
    this.transferredFromUserId,
    this.upgradeStars = 0,
    this.transferStars = 0,
    this.totalSupply,
    this.convertedAt,
    this.createdAt,
  });

  final int id;
  final int ownerId;
  final int? senderId;
  final int? giftId;
  final int? messageId;
  final int stars;
  final String slug;
  final String title;
  final String emoji;
  final String? note;
  final String status;
  final bool isDisplayed;
  final bool isCollectible;
  final int? serial;
  final int? transferredFromUserId;
  final int upgradeStars;
  final int transferStars;
  final int? totalSupply;
  final DateTime? convertedAt;
  final DateTime? createdAt;

  bool get canConvert =>
      !isCollectible && (status == 'held' || status == 'kept');

  bool get canUpgrade =>
      !isCollectible &&
      upgradeStars > 0 &&
      (status == 'held' || status == 'kept');

  bool get canTransfer => status == 'held' || status == 'kept';

  String get serialLabel {
    if (!isCollectible || serial == null) return '';
    if (totalSupply != null) return '#$serial / $totalSupply';
    return '#$serial';
  }

  factory UserStarGift.fromJson(Map<String, dynamic> json) => UserStarGift(
        id: json['id'] as int? ?? 0,
        ownerId: json['owner_id'] as int? ?? 0,
        senderId: json['sender_id'] as int?,
        giftId: json['gift_id'] as int?,
        messageId: json['message_id'] as int?,
        stars: json['stars'] as int? ?? 0,
        slug: json['slug'] as String? ?? 'gift',
        title: json['title'] as String? ?? 'Подарок',
        emoji: json['emoji'] as String? ?? '🎁',
        note: json['note'] as String?,
        status: json['status'] as String? ?? 'held',
        isDisplayed: json['is_displayed'] as bool? ?? true,
        isCollectible: json['is_collectible'] as bool? ?? false,
        serial: json['serial'] as int?,
        transferredFromUserId: json['transferred_from_user_id'] as int?,
        upgradeStars: json['upgrade_stars'] as int? ?? 0,
        transferStars: json['transfer_stars'] as int? ?? 0,
        totalSupply: json['total_supply'] as int?,
        convertedAt: DateTime.tryParse(json['converted_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

class ConvertGiftResult {
  const ConvertGiftResult({
    required this.gift,
    required this.balance,
  });

  final UserStarGift gift;
  final int balance;

  factory ConvertGiftResult.fromJson(Map<String, dynamic> json) =>
      ConvertGiftResult(
        gift: UserStarGift.fromJson(
          json['gift'] as Map<String, dynamic>? ?? const {},
        ),
        balance: json['balance'] as int? ?? 0,
      );
}

class ChannelSubscriptionInfo {
  const ChannelSubscriptionInfo({
    required this.channelId,
    required this.status,
    this.amountStars = 0,
    this.expiresAt,
    this.autoRenew = false,
    this.isActive = false,
    this.monthlyPriceStars = 0,
  });

  final int channelId;
  final String status;
  final int amountStars;
  final DateTime? expiresAt;
  final bool autoRenew;
  final bool isActive;
  final int monthlyPriceStars;

  factory ChannelSubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      ChannelSubscriptionInfo(
        channelId: json['channel_id'] as int? ?? 0,
        status: json['status'] as String? ?? 'none',
        amountStars: json['amount_stars'] as int? ?? 0,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        autoRenew: json['auto_renew'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? false,
        monthlyPriceStars: json['monthly_price_stars'] as int? ?? 0,
      );
}

class PaidMessageExceptionUser {
  const PaidMessageExceptionUser({
    required this.id,
    this.name,
    this.username,
    this.avatarUrl,
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return u.startsWith('@') ? u : '@$u';
    return 'Пользователь';
  }

  factory PaidMessageExceptionUser.fromJson(Map<String, dynamic> json) =>
      PaidMessageExceptionUser(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String?,
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class StarGiveaway {
  const StarGiveaway({
    required this.id,
    required this.channelId,
    required this.creatorUserId,
    required this.prizeStars,
    required this.winnersCount,
    required this.totalEscrowStars,
    required this.status,
    required this.endsAt,
    this.requireMembership = true,
    this.participantsCount = 0,
    this.title,
    this.completedAt,
    this.createdAt,
    this.joinedByMe = false,
    this.isWinner = false,
  });

  final int id;
  final int channelId;
  final int creatorUserId;
  final int prizeStars;
  final int winnersCount;
  final int totalEscrowStars;
  final String status;
  final DateTime endsAt;
  final bool requireMembership;
  final int participantsCount;
  final String? title;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final bool joinedByMe;
  final bool isWinner;

  bool get isActive => status == 'active';

  factory StarGiveaway.fromJson(Map<String, dynamic> json) => StarGiveaway(
        id: json['id'] as int? ?? 0,
        channelId: json['channel_id'] as int? ?? 0,
        creatorUserId: json['creator_user_id'] as int? ?? 0,
        prizeStars: json['prize_stars'] as int? ?? 0,
        winnersCount: json['winners_count'] as int? ?? 0,
        totalEscrowStars: json['total_escrow_stars'] as int? ?? 0,
        status: json['status'] as String? ?? 'active',
        endsAt: DateTime.tryParse(json['ends_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        requireMembership: json['require_membership'] as bool? ?? true,
        participantsCount: json['participants_count'] as int? ?? 0,
        title: json['title'] as String?,
        completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        joinedByMe: json['joined_by_me'] as bool? ?? false,
        isWinner: json['is_winner'] as bool? ?? false,
      );
}

class StarInvoice {
  const StarInvoice({
    required this.id,
    required this.botId,
    required this.creatorUserId,
    required this.title,
    required this.amountStars,
    required this.status,
    this.payerUserId,
    this.description,
    this.payload,
    this.expiresAt,
    this.paidAt,
    this.createdAt,
    this.botUsername,
    this.botName,
  });

  final int id;
  final int botId;
  final int creatorUserId;
  final int? payerUserId;
  final String title;
  final String? description;
  final int amountStars;
  final String? payload;
  final String status;
  final DateTime? expiresAt;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final String? botUsername;
  final String? botName;

  bool get isPayable => status == 'pending';

  factory StarInvoice.fromJson(Map<String, dynamic> json) => StarInvoice(
        id: json['id'] as int? ?? 0,
        botId: json['bot_id'] as int? ?? 0,
        creatorUserId: json['creator_user_id'] as int? ?? 0,
        payerUserId: json['payer_user_id'] as int?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        amountStars: json['amount_stars'] as int? ?? 0,
        payload: json['payload'] as String?,
        status: json['status'] as String? ?? 'pending',
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        botUsername: json['bot_username'] as String?,
        botName: json['bot_name'] as String?,
      );
}

class PayInvoiceResult {
  const PayInvoiceResult({
    required this.invoice,
    required this.balance,
  });

  final StarInvoice invoice;
  final int balance;

  factory PayInvoiceResult.fromJson(Map<String, dynamic> json) =>
      PayInvoiceResult(
        invoice: StarInvoice.fromJson(
          json['invoice'] as Map<String, dynamic>? ?? const {},
        ),
        balance: json['balance'] as int? ?? 0,
      );
}
