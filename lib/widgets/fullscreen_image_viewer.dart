import 'package:flutter/material.dart';
import 'recipe_network_image.dart';

/// Полноэкранный просмотрщик изображений с возможностью листания (как в Telegram)
class FullscreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? heroTag;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTag,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView для листания изображений
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _ZoomableImage(
                key: ValueKey(index),
                rawUrl: widget.imageUrls[index],
                onTap: _toggleControls,
              );
            },
          ),
          
          // Верхняя панель с кнопкой закрытия
          if (_showControls)
            SafeArea(
              child: Column(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: widget.imageUrls.length > 1
                        ? Text(
                            '${_currentIndex + 1} / ${widget.imageUrls.length}',
                            style: const TextStyle(color: Colors.white),
                          )
                        : null,
                    centerTitle: true,
                  ),
                ],
              ),
            ),
          
          // Индикатор страниц (если больше одного изображения)
          if (_showControls && widget.imageUrls.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.imageUrls.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Виджет для отображения изображения с возможностью масштабирования
/// который не блокирует горизонтальные свайпы PageView
class _ZoomableImage extends StatefulWidget {
  final String rawUrl;
  final VoidCallback onTap;

  const _ZoomableImage({
    super.key,
    required this.rawUrl,
    required this.onTap,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  TransformationController? _transformationController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController!.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController?.removeListener(_onTransformationChanged);
    _transformationController?.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController!.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.01;
    if (_isZoomed != isZoomed) {
      setState(() {
        _isZoomed = isZoomed;
      });
    }
  }

  void _resetZoom() {
    _transformationController?.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _resetZoom();
    } else {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final size = box.size;
        final position = Offset(size.width / 2, size.height / 2);
        _transformationController?.value = Matrix4.identity()
          ..translateByDouble(-position.dx, -position.dy, 0, 1)
          ..scaleByDouble(2.0, 2.0, 1, 1)
          ..translateByDouble(position.dx, position.dy, 0, 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isZoomed ? _resetZoom : widget.onTap,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 4.0,
        // Ключевой момент: панорамирование отключено, чтобы не блокировать горизонтальные свайпы PageView
        // Масштабирование работает только пинчем (двумя пальцами)
        panEnabled: false, // Отключаем панорамирование полностью
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: Center(
          child: RecipeNetworkImage(
            rawUrl: widget.rawUrl,
            profile: RecipeImageProfile.fullscreen,
            fit: BoxFit.contain,
            placeholder: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: const Icon(
              Icons.error,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}

/// Функция-помощник для открытия полноэкранного просмотра изображений
void showFullscreenImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  String? heroTag,
}) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (context) => FullscreenImageViewer(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
      fullscreenDialog: true,
    ),
  );
}
