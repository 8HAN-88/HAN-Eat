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
  final VoidCallback? onTap; // Обработчик клика (для постов - открыть детальную страницу)
  final bool enableFullscreen; // Включить полноэкранный просмотр при клике на фото

  const TelegramPhotoGrid({
    super.key,
    required this.imageUrls,
    this.maxHeight = 300,
    this.spacing = 2,
    this.borderRadius,
    this.onTap,
    this.enableFullscreen = true, // По умолчанию включен
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    if (imageUrls.length == 1) {
      return _buildSingleImage(context, imageUrls[0]);
    }
    if (imageUrls.length == 2) {
      return _buildTwoImages(context, imageUrls);
    }
    if (imageUrls.length == 3) {
      return _buildThreeImages(context, imageUrls);
    }
    if (imageUrls.length == 4) {
      return _buildFourImages(context, imageUrls);
    }
    // Для 5+ изображений используем сетку
    return _buildGridImages(context, imageUrls);
  }

  Widget _buildSingleImage(BuildContext context, String url) {
    // Для одного изображения используем квадратное соотношение как в Instagram
    final imageWidget = AspectRatio(
      aspectRatio: 1,
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
                      child: _buildImage(urls[1], double.infinity, maxHeight / 2 - spacing / 2),
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
                      child: _buildImage(urls[2], double.infinity, maxHeight / 2 - spacing / 2),
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
                      child: _buildImage(urls[0], double.infinity, maxHeight / 2 - spacing / 2),
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
                      child: _buildImage(urls[1], double.infinity, maxHeight / 2 - spacing / 2),
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
                      child: _buildImage(urls[2], double.infinity, maxHeight / 2 - spacing / 2),
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
                      child: _buildImage(urls[3], double.infinity, maxHeight / 2 - spacing / 2),
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
    final isLocalFile = !url.startsWith('http://') && !url.startsWith('https://');
    
    // Локальный API часто отдаёт localhost:5000 — подставляем baseUrl (порт 5001 и т.д.)
    final resolvedUrl = isLocalFile ? url : ServerConfig.resolveMediaUrl(url);
    final optimizedUrl =
        isLocalFile ? resolvedUrl : getOptimizedImageUrl(resolvedUrl);
    
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
          child: const Center(child: CircularProgressIndicator()),
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
