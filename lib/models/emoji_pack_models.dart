class CustomEmojiItem {
  const CustomEmojiItem({
    required this.id,
    required this.mediaUrl,
    this.shortcode,
    this.orderIndex = 0,
  });

  final int id;
  final String mediaUrl;
  final String? shortcode;
  final int orderIndex;

  factory CustomEmojiItem.fromJson(Map<String, dynamic> json) {
    return CustomEmojiItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaUrl: json['media_url'] as String? ?? '',
      shortcode: json['shortcode'] as String?,
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
    );
  }
}

class EmojiPack {
  const EmojiPack({
    required this.id,
    required this.title,
    required this.slug,
    required this.ownerUserId,
    this.ownerName = '',
    required this.isPublic,
    required this.isInstalled,
    this.isOwned = false,
    this.isPurchased = false,
    this.isListed = false,
    this.priceStars = 0,
    this.feeStars = 0,
    required this.items,
    required this.itemsCount,
    this.shareLink,
  });

  final int id;
  final String title;
  final String slug;
  final int ownerUserId;
  final String ownerName;
  final bool isPublic;
  final bool isInstalled;
  final bool isOwned;
  final bool isPurchased;
  final bool isListed;
  final int priceStars;
  final int feeStars;
  final List<CustomEmojiItem> items;
  final int itemsCount;
  final String? shareLink;

  String get authorLabel {
    final name = ownerName.trim();
    if (name.isNotEmpty) return name;
    return 'id$ownerUserId';
  }

  bool get canUse =>
      isOwned || isPurchased || (isInstalled && priceStars <= 0);

  bool get isOnSale => isListed && priceStars > 0;

  EmojiPack copyWith({
    String? title,
    bool? isPublic,
    bool? isInstalled,
    List<CustomEmojiItem>? items,
    int? itemsCount,
  }) {
    return EmojiPack(
      id: id,
      title: title ?? this.title,
      slug: slug,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      isPublic: isPublic ?? this.isPublic,
      isInstalled: isInstalled ?? this.isInstalled,
      isOwned: isOwned,
      isPurchased: isPurchased,
      isListed: isListed,
      priceStars: priceStars,
      feeStars: feeStars,
      items: items ?? this.items,
      itemsCount: itemsCount ?? this.itemsCount,
      shareLink: shareLink,
    );
  }

  factory EmojiPack.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return EmojiPack(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      ownerUserId: (json['owner_user_id'] as num?)?.toInt() ?? 0,
      ownerName: json['owner_name'] as String? ?? '',
      isPublic: json['is_public'] as bool? ?? false,
      isInstalled: json['is_installed'] as bool? ?? false,
      isOwned: json['is_owned'] as bool? ?? false,
      isPurchased: json['is_purchased'] as bool? ?? false,
      isListed: json['is_listed'] as bool? ??
          ((json['price_stars'] as num?)?.toInt() ?? 0) > 0,
      priceStars: (json['price_stars'] as num?)?.toInt() ?? 0,
      feeStars: (json['fee_stars'] as num?)?.toInt() ?? 0,
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(CustomEmojiItem.fromJson)
          .toList(),
      itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
      shareLink: json['share_link'] as String?,
    );
  }
}
