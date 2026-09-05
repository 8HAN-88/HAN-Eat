import '../../services/ads_service.dart';

class AdOrderIssue {
  const AdOrderIssue(this.field, this.message);
  final String field;
  final String message;
}

String normalizeAdDestinationUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return trimmed;
  }
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  return 'https://$trimmed';
}

bool isAdDestinationUrl(String raw) {
  final url = normalizeAdDestinationUrl(raw);
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.isScheme('https') || uri.isScheme('http')) &&
      (uri.host.trim().isNotEmpty);
}

int? parseAdPostId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final direct = int.tryParse(trimmed);
  if (direct != null && direct > 0) return direct;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length; i++) {
    if ((segs[i] == 'post' || segs[i] == 'posts') && i + 1 < segs.length) {
      final id = int.tryParse(segs[i + 1]);
      if (id != null && id > 0) return id;
    }
  }
  if (segs.isNotEmpty) {
    final last = int.tryParse(segs.last);
    if (last != null && last > 0) return last;
  }
  return null;
}

List<AdOrderIssue> validateAdOrder({
  required Set<String> surfaces,
  required String title,
  required String body,
  required String? imageUrl,
  required String destinationType,
  required String destinationUrl,
  required int? channelId,
  required String postIdRaw,
}) {
  final issues = <AdOrderIssue>[];
  if (surfaces.isEmpty) {
    issues.add(const AdOrderIssue('surfaces', 'Выберите, где показывать объявление'));
  }
  if (title.trim().isEmpty) {
    issues.add(const AdOrderIssue('title', 'Напишите заголовок — его увидят в карточке'));
  }
  if (body.trim().isEmpty && (imageUrl ?? '').trim().isEmpty) {
    issues.add(
      const AdOrderIssue(
        'creative',
        'Добавьте текст или картинку — иначе нечего показывать',
      ),
    );
  }
  switch (destinationType) {
    case 'url':
      if (!isAdDestinationUrl(destinationUrl)) {
        issues.add(
          const AdOrderIssue(
            'destination',
            'Укажите ссылку, куда вести по нажатию — можно без https://',
          ),
        );
      }
    case 'channel':
      if (channelId == null) {
        issues.add(
          const AdOrderIssue(
            'destination',
            'Выберите канал или поставьте обычную ссылку',
          ),
        );
      }
    case 'post':
      if (parseAdPostId(postIdRaw) == null) {
        issues.add(
          const AdOrderIssue(
            'destination',
            'Вставьте ссылку на пост или его номер',
          ),
        );
      }
  }
  return issues;
}

class FeedAdPlacement {
  const FeedAdPlacement({
    required this.insertBeforePostIndex,
    required this.item,
  });

  final int insertBeforePostIndex;
  final FeedAdItem item;
}

class FeedRow {
  const FeedRow.post(this.post, this.postPosition) : ad = null;
  const FeedRow.ad(this.ad)
      : post = null,
        postPosition = null;

  final dynamic post;
  final FeedAdItem? ad;
  final int? postPosition;

  bool get isAd => ad != null;
}

List<FeedRow> mergeFeedRows({
  required List<dynamic> posts,
  required List<FeedAdPlacement> ads,
}) {
  final byIndex = <int, FeedAdItem>{};
  for (final ad in ads) {
    byIndex[ad.insertBeforePostIndex] = ad.item;
  }
  final rows = <FeedRow>[];
  for (var i = 0; i < posts.length; i++) {
    final ad = byIndex.remove(i);
    if (ad != null) rows.add(FeedRow.ad(ad));
    rows.add(FeedRow.post(posts[i], i));
  }
  final leftover = byIndex.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in leftover) {
    rows.add(FeedRow.ad(entry.value));
  }
  return rows;
}

String adOrderSupportPath() {
  return '/support?subject=${Uri.encodeComponent('Реклама в HanWe')}'
      '&message=${Uri.encodeComponent('Хочу заказать рекламу. Подскажите, как лучше разместить объявление.')}';
}
