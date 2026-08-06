class GifCatalogItem {
  const GifCatalogItem({
    required this.id,
    required this.previewUrl,
    required this.url,
    this.title = '',
    this.width,
    this.height,
  });

  final String id;
  final String previewUrl;
  final String url;
  final String title;
  final int? width;
  final int? height;

  factory GifCatalogItem.fromJson(Map<String, dynamic> json) {
    return GifCatalogItem(
      id: json['id'] as String? ?? '',
      previewUrl: json['preview_url'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}

class GifCatalogPage {
  const GifCatalogPage({
    required this.configured,
    required this.items,
    this.next,
  });

  final bool configured;
  final List<GifCatalogItem> items;
  final String? next;

  factory GifCatalogPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final nextRaw = (json['next'] as String?)?.trim();
    return GifCatalogPage(
      configured: json['configured'] as bool? ?? true,
      next: (nextRaw == null || nextRaw.isEmpty) ? null : nextRaw,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(GifCatalogItem.fromJson)
          .where((e) => e.url.isNotEmpty)
          .toList(),
    );
  }
}
