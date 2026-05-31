import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/image_url_helper.dart';

/// Профиль качества: сетка — быстро и чётко; деталь — сначала превью, затем HD.
enum RecipeImageProfile { card, detailHero, fullscreen }

const _kRecipeImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

final CacheManager recipeImageCacheManager = CacheManager(
  Config(
    'recipeImages',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 300,
  ),
);

/// Последовательно прогревает кэш (8 параллельных запросов к Spoonacular часто «зависают»).
Future<void> warmRecipeImageCache(Iterable<String> rawUrls) async {
  for (final raw in rawUrls) {
    if (raw.trim().isEmpty) continue;
    try {
      await recipeImageCacheManager.downloadFile(getRecipeCardImageUrl(raw));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Изображение рецепта с fallback по размерам и прогрессивным HD на экране рецепта.
class RecipeNetworkImage extends StatefulWidget {
  const RecipeNetworkImage({
    super.key,
    required this.rawUrl,
    this.profile = RecipeImageProfile.card,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheKey,
    this.placeholder,
    this.errorWidget,
  });

  final String rawUrl;
  final RecipeImageProfile profile;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? cacheKey;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<RecipeNetworkImage> createState() => _RecipeNetworkImageState();
}

class _RecipeNetworkImageState extends State<RecipeNetworkImage> {
  int _attempt = 0;
  bool _hiResReady = false;
  bool _triedNextOnError = false;

  List<String> get _candidates {
    final raw = widget.rawUrl.trim();
    if (raw.isEmpty) return const [];
    switch (widget.profile) {
      case RecipeImageProfile.card:
        return [
          getRecipeImageUrl(raw, spoonacularDimensions: '240x150'),
          getRecipeImageUrl(raw, spoonacularDimensions: '312x231'),
        ];
      case RecipeImageProfile.detailHero:
      case RecipeImageProfile.fullscreen:
        return [
          getRecipeImageUrl(raw, spoonacularDimensions: '556x370'),
          getRecipeImageUrl(raw, spoonacularDimensions: '312x231'),
          getRecipeImageUrl(raw, spoonacularDimensions: '240x150'),
        ];
    }
  }

  String get _previewUrl =>
      getRecipeImageUrl(widget.rawUrl.trim(), spoonacularDimensions: '312x231');

  String get _hiResUrl =>
      getRecipeImageUrl(widget.rawUrl.trim(), spoonacularDimensions: '556x370');

  void _tryNextCandidate() {
    if (_triedNextOnError) return;
    _triedNextOnError = true;
    if (_attempt + 1 < _candidates.length && mounted) {
      setState(() {
        _attempt++;
        _hiResReady = false;
        _triedNextOnError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    if (candidates.isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    if (widget.profile == RecipeImageProfile.detailHero) {
      return _buildProgressiveHero();
    }

    final url = candidates[_attempt.clamp(0, candidates.length - 1)];
    return _buildCached(url: url, showPlaceholder: true);
  }

  Widget _buildProgressiveHero() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCached(url: _previewUrl, showPlaceholder: true),
        if (_hiResReady)
          _buildCached(url: _hiResUrl, showPlaceholder: false)
        else
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: Opacity(
              opacity: 0.01,
              child: _buildCached(
                url: _hiResUrl,
                showPlaceholder: false,
                onLoaded: () {
                  if (mounted) setState(() => _hiResReady = true);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCached({
    required String url,
    required bool showPlaceholder,
    VoidCallback? onLoaded,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetW = widget.width != null ? (widget.width! * dpr).round() : null;

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: widget.cacheKey != null ? '${widget.cacheKey!}|$url' : null,
      cacheManager: recipeImageCacheManager,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      httpHeaders: _kRecipeImageHeaders,
      memCacheWidth: targetW != null ? targetW.clamp(400, 1400) : 900,
      fadeInDuration: const Duration(milliseconds: 280),
      fadeOutDuration: Duration.zero,
      placeholder: showPlaceholder
          ? (context, _) =>
              widget.placeholder ??
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
          : (_, __) => const SizedBox.shrink(),
      imageBuilder: (context, imageProvider) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded?.call());
        return Image(
          image: imageProvider,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
      errorWidget: (context, failedUrl, error) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNextCandidate());
        return widget.errorWidget ??
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.restaurant_menu,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 40,
              ),
            );
      },
    );
  }
}
