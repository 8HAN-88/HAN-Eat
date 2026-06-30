// Модели для системы донатов

class DonationCreateRequest {
  final int recipientId;
  final int? channelId;
  final int? postId;
  final int amountStars;
  final String? message;

  DonationCreateRequest({
    required this.recipientId,
    this.channelId,
    this.postId,
    required this.amountStars,
    this.message,
  });

  Map<String, dynamic> toJson() => {
        'recipient_id': recipientId,
        if (channelId != null) 'channel_id': channelId,
        if (postId != null) 'post_id': postId,
        'amount_stars': amountStars,
        if (message != null && message!.isNotEmpty) 'message': message,
      };
}

class Donation {
  final int id;
  final int? senderId;
  final int recipientId;
  final int? channelId;
  final int? postId;
  final int amountStars;
  final String? message;
  final String status;
  final DateTime createdAt;

  Donation({
    required this.id,
    this.senderId,
    required this.recipientId,
    this.channelId,
    this.postId,
    required this.amountStars,
    this.message,
    required this.status,
    required this.createdAt,
  });

  factory Donation.fromJson(Map<String, dynamic> json) => Donation(
        id: json['id'] as int,
        senderId: json['sender_id'] as int?,
        recipientId: json['recipient_id'] as int,
        channelId: json['channel_id'] as int?,
        postId: json['post_id'] as int?,
        amountStars: json['amount_stars'] as int,
        message: json['message'] as String?,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
