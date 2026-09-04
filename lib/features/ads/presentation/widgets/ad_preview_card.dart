import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../services/ads_service.dart';
import '../../../../services/server_config.dart';

/// Instagram-like preview of how a client ad will look in Recommendations.
class AdPreviewCard extends StatelessWidget {
  const AdPreviewCard({
    super.key,
    required this.campaign,
  });

  final AdCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creative = campaign.creative;
    final rawImage = (creative.imageUrl ?? '').trim();
    final imageUrl =
        rawImage.isEmpty ? null : ServerConfig.resolveMediaUrl(rawImage);
    final advertiser = (creative.advertiserName ?? '').trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(
                    advertiser.isEmpty
                        ? 'Р'
                        : advertiser.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        advertiser.isEmpty ? 'Рекламодатель' : advertiser,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'Реклама · ${campaign.surfacesLabel}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Реклама',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (imageUrl != null && imageUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 4 / 5,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.image_outlined, size: 36)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (creative.title.trim().isNotEmpty)
                  Text(
                    creative.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (creative.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(creative.body),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: null,
                  child: Text(
                    creative.ctaLabel.trim().isEmpty
                        ? 'Подробнее'
                        : creative.ctaLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
