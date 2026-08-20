class StickerItem {
  const StickerItem({
    required this.id,
    required this.mediaUrl,
    this.emoji,
    this.stickerType = 'static',
    this.orderIndex = 0,
  });

  final int id;
  final String mediaUrl;
  final String? emoji;
  final String stickerType;
  final int orderIndex;

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaUrl: json['media_url'] as String? ?? '',
      emoji: json['emoji'] as String?,
      stickerType: json['sticker_type'] as String? ?? 'static',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
    );
  }
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.title,
    required this.slug,
    required this.ownerUserId,
    this.ownerName = '',
    required this.isPublic,
    this.isPremium = false,
    required this.isInstalled,
    this.isOwned = false,
    this.isPurchased = false,
    this.priceStars = 0,
    this.feeStars = 0,
    required this.stickers,
    required this.stickersCount,
    this.shareLink,
  });

  final int id;
  final String title;
  final String slug;
  final int ownerUserId;
  final String ownerName;
  final bool isPublic;
  final bool isPremium;
  final bool isInstalled;
  final bool isOwned;
  final bool isPurchased;
  final int priceStars;
  final int feeStars;
  final List<StickerItem> stickers;
  final int stickersCount;
  final String? shareLink;

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    final rawStickers = json['stickers'] as List<dynamic>? ?? const [];
    return StickerPack(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      ownerUserId: (json['owner_user_id'] as num?)?.toInt() ?? 0,
      ownerName: json['owner_name'] as String? ?? '',
      isPublic: json['is_public'] as bool? ?? false,
      isPremium: json['is_premium'] as bool? ?? false,
      isInstalled: json['is_installed'] as bool? ?? false,
      isOwned: json['is_owned'] as bool? ?? false,
      isPurchased: json['is_purchased'] as bool? ?? false,
      priceStars: (json['price_stars'] as num?)?.toInt() ?? 0,
      feeStars: (json['fee_stars'] as num?)?.toInt() ?? 0,
      stickers: rawStickers
          .whereType<Map<String, dynamic>>()
          .map(StickerItem.fromJson)
          .toList(),
      stickersCount: (json['stickers_count'] as num?)?.toInt() ?? 0,
      shareLink: json['share_link'] as String?,
    );
  }
}

class StickerFavoriteItem {
  const StickerFavoriteItem({
    required this.id,
    required this.mediaUrl,
    this.emoji,
    this.stickerType = 'static',
    this.packId = 0,
  });

  final int id;
  final String mediaUrl;
  final String? emoji;
  final String stickerType;
  final int packId;

  factory StickerFavoriteItem.fromJson(Map<String, dynamic> json) {
    return StickerFavoriteItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaUrl: json['media_url'] as String? ?? '',
      emoji: json['emoji'] as String?,
      stickerType: json['sticker_type'] as String? ?? 'static',
      packId: (json['pack_id'] as num?)?.toInt() ?? 0,
    );
  }
}
