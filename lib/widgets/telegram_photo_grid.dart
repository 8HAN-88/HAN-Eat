import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/server_config.dart';
import '../utils/file_helper.dart';
import '../utils/image_url_helper.dart';
import 'fullscreen_image_viewer.dart';

/// Виджет для отображения нескольких фотографий в стиле Telegram
class TelegramPhotoGrid extends StatelessWidget {
  final List<String> imageUrls; // Пути к файлам или URL
  final double maxHeight;
  final double spacing;
  final BorderRadius? borderRadius;
  final VoidCallback?
      onTap; // Обработчик клика (для постов - открыть детальную страницу)
  final bool
      enableFullscreen; // Включить полноэкранный просмотр при клике на фото
  final double singleAspectRatio;

  const TelegramPhotoGrid({
    super.key,
    required this.imageUrls,
    this.maxHeight = 300,
    this.spacing = 2,
    this.borderRadius,
    this.onTap,
    this.enableFullscreen = true, // По умолчанию включен
    this.singleAspectRatio = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    if (imageUrls.length == 1) {
      return _buildSingleImage(context, imageUrls[0]);
    }
    return _ModernPhotoCarousel(
      imageUrls: imageUrls,
      maxHeight: maxHeight,
      borderRadius: borderRadius ?? BorderRadius.circular(18),
      onTap: onTap,
      enableFullscreen: enableFullscreen,
    );
  }

  Widget _buildSingleImage(BuildContext context, String url) {
    final imageWidget = AspectRatio(
      aspectRatio: singleAspectRatio,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        child: _buildImage(url, double.infinity, double.infinity),
      ),
    );

    return GestureDetector(
      onTap: () => _handleImageTap(context, 0),
      child: imageWidget,
    );
  }

  Widget _buildTwoImages(BuildContext context, List<String> urls) {
    final content = SizedBox(
      height: maxHeight,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _handleImageTap(context, 0),
              child: ClipRRect(
                borderRadius: borderRadius != null
                    ? BorderRadius.only(
                        topLeft: borderRadius!.topLeft,
                        bottomLeft: borderRadius!.bottomLeft,
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                child: _buildImage(urls[0], double.infinity, maxHeight),
              ),
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: GestureDetector(
              onTap: () => _handleImageTap(context, 1),
              child: ClipRRect(
                borderRadius: borderRadius != null
                    ? BorderRadius.only(
                        topRight: borderRadius!.topRight,
                        bottomRight: borderRadius!.bottomRight,
                      )
                    : const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                child: _buildImage(urls[1], double.infinity, maxHeight),
              ),
            ),
          ),
        ],
      ),
    );

    return content;
  }

  void _handleImageTap(BuildContext context, int index) {
    if (enableFullscreen) {
      showFullscreenImageViewer(
        context,
        imageUrls: imageUrls,
        initialIndex: index,
      );
    } else if (onTap != null) {
      onTap!();
    }
  }

  Widget _buildThreeImages(BuildContext context, List<String> urls) {
    final content = SizedBox(
      height: maxHeight,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _handleImageTap(context, 0),
              child: ClipRRect(
                borderRadius: borderRadius != null
                    ? BorderRadius.only(
                        topLeft: borderRadius!.topLeft,
                        bottomLeft: borderRadius!.bottomLeft,
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                child: _buildImage(urls[0], double.infinity, maxHeight),
              ),
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 1),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              topRight: borderRadius!.topRight,
                            )
                          : const BorderRadius.only(
                              topRight: Radius.circular(12),
                            ),
                      child: _buildImage(urls[1], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
                SizedBox(height: spacing),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 2),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              bottomRight: borderRadius!.bottomRight,
                            )
                          : const BorderRadius.only(
                              bottomRight: Radius.circular(12),
                            ),
                      child: _buildImage(urls[2], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return content;
  }

  Widget _buildFourImages(BuildContext context, List<String> urls) {
    final content = SizedBox(
      height: maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 0),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              topLeft: borderRadius!.topLeft,
                            )
                          : const BorderRadius.only(
                              topLeft: Radius.circular(12),
                            ),
                      child: _buildImage(urls[0], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 1),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              topRight: borderRadius!.topRight,
                            )
                          : const BorderRadius.only(
                              topRight: Radius.circular(12),
                            ),
                      child: _buildImage(urls[1], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 2),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              bottomLeft: borderRadius!.bottomLeft,
                            )
                          : const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                            ),
                      child: _buildImage(urls[2], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleImageTap(context, 3),
                    child: ClipRRect(
                      borderRadius: borderRadius != null
                          ? BorderRadius.only(
                              bottomRight: borderRadius!.bottomRight,
                            )
                          : const BorderRadius.only(
                              bottomRight: Radius.circular(12),
                            ),
                      child: _buildImage(urls[3], double.infinity,
                          maxHeight / 2 - spacing / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return content;
  }

  Widget _buildGridImages(BuildContext context, List<String> urls) {
    // Для 5+ изображений показываем первые 4 и счетчик остальных
    final displayUrls = urls.take(4).toList();
    final remaining = urls.length - 4;

    final content = GestureDetector(
      onTap: () => _handleImageTap(context, 0),
      child: Stack(
        children: [
          _buildFourImages(context, displayUrls),
          if (remaining > 0)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: borderRadius ?? BorderRadius.circular(12),
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Text(
                      '+$remaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return content;
  }

  Widget _buildImage(String url, double width, double height) {
    // Проверяем, является ли это локальным файлом или URL
    final isLocalFile =
        !url.startsWith('http://') && !url.startsWith('https://');

    // Локальный API часто отдаёт localhost:5000 — подставляем baseUrl (порт 5001 и т.д.)
    final resolvedUrl = isLocalFile ? url : ServerConfig.resolveMediaUrl(url);
    final optimizedUrl = isLocalFile
        ? resolvedUrl
        : ServerConfig.resolvePublisherAvatarUrl(
            getOptimizedImageUrl(resolvedUrl),
          );

    if (isLocalFile) {
      if (kIsWeb) {
        // На веб используем Image.network с path из XFile
        return Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } else {
        final file = getFileFromPath(url);
        if (file == null) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.error, color: Colors.red),
          );
        }
        return Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      }
    } else {
      // Это URL, используем CachedNetworkImage с оптимизированным URL
      // Проверяем, что width и height не равны infinity перед преобразованием в int
      final memCacheWidth = width.isFinite ? (width * 2).toInt() : 1200;
      final memCacheHeight = height.isFinite ? (height * 2).toInt() : 800;

      return CachedNetworkImage(
        imageUrl: optimizedUrl,
        width: width.isFinite ? width : null,
        height: height.isFinite ? height : null,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        httpHeaders: const {
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'User-Agent': 'HAN-Eat/1.0 (Flutter)',
        },
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        maxWidthDiskCache: 1200,
        maxHeightDiskCache: 800,
        placeholder: (context, url) => Container(
          width: width.isFinite ? width : double.infinity,
          height: height.isFinite ? height : maxHeight,
          color: Colors.grey[300],
        ),
        errorWidget: (context, url, error) => Container(
          width: width.isFinite ? width : double.infinity,
          height: height.isFinite ? height : maxHeight,
          color: Colors.grey[300],
          child: const Icon(Icons.error, color: Colors.red),
        ),
      );
    }
  }
}

class _ModernPhotoCarousel extends StatefulWidget {
  const _ModernPhotoCarousel({
    required this.imageUrls,
    required this.maxHeight,
    required this.borderRadius,
    required this.enableFullscreen,
    this.onTap,
  });

  final List<String> imageUrls;
  final double maxHeight;
  final BorderRadius borderRadius;
  final bool enableFullscreen;
  final VoidCallback? onTap;

  @override
  State<_ModernPhotoCarousel> createState() => _ModernPhotoCarouselState();
}

class _ModernPhotoCarouselState extends State<_ModernPhotoCarousel> {
  late final PageController _controller;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: widget.borderRadius,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handleTap(context, index),
                  child: _buildImage(
                    context,
                    widget.imageUrls[index],
                    double.infinity,
                    widget.maxHeight,
                  ),
                );
              },
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.32),
                      ],
                      stops: const [0, 0.22, 0.68, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: _GlassPill(
                child: Text(
                  '${_currentIndex + 1}/${widget.imageUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (index) {
                  final selected = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: selected ? 0.95 : 0.48,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, int index) {
    if (widget.enableFullscreen) {
      showFullscreenImageViewer(
        context,
        imageUrls: widget.imageUrls,
        initialIndex: index,
      );
    } else {
      widget.onTap?.call();
    }
  }

  Widget _buildImage(
    BuildContext context,
    String url,
    double width,
    double height,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isLocalFile =
        !url.startsWith('http://') && !url.startsWith('https://');
    final resolvedUrl = isLocalFile ? url : ServerConfig.resolveMediaUrl(url);
    final optimizedUrl = isLocalFile
        ? resolvedUrl
        : ServerConfig.resolvePublisherAvatarUrl(
            getOptimizedImageUrl(resolvedUrl),
          );

    Widget fallback(IconData icon, {Color? color}) {
      return Container(
        width: width.isFinite ? width : double.infinity,
        height: height.isFinite ? height : widget.maxHeight,
        color: scheme.surfaceContainerHighest,
        child: Icon(icon, color: color ?? scheme.onSurfaceVariant),
      );
    }

    if (isLocalFile) {
      if (kIsWeb) {
        return Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              fallback(Icons.error_outline, color: scheme.error),
        );
      }
      final file = getFileFromPath(url);
      if (file == null) {
        return fallback(Icons.error_outline, color: scheme.error);
      }
      return Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            fallback(Icons.error_outline, color: scheme.error),
      );
    }

    final memCacheWidth = width.isFinite ? (width * 2).toInt() : 1200;
    final memCacheHeight = height.isFinite ? (height * 2).toInt() : 1200;
    return CachedNetworkImage(
      imageUrl: optimizedUrl,
      width: width.isFinite ? width : null,
      height: height.isFinite ? height : null,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: Duration.zero,
      httpHeaders: const {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'User-Agent': 'HAN-Eat/1.0 (Flutter)',
      },
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      maxWidthDiskCache: 1200,
      maxHeightDiskCache: 1200,
      placeholder: (context, url) => Container(
        width: width.isFinite ? width : double.infinity,
        height: height.isFinite ? height : widget.maxHeight,
        color: scheme.surfaceContainerHighest,
      ),
      errorWidget: (context, url, error) =>
          fallback(Icons.error_outline, color: scheme.error),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: child,
      ),
    );
  }
}
