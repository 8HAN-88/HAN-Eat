import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../services/server_config.dart';
import '../data/story_service.dart';

/// Один элемент сторис
class StoryItem {
  final String id;
  final String mediaUrl;
  final String? authorName;
  final String? authorAvatar;
  final Duration duration;
  final bool isVideo;

  StoryItem({
    required this.id,
    required this.mediaUrl,
    this.authorName,
    this.authorAvatar,
    this.duration = const Duration(seconds: 5),
    this.isVideo = false,
  });
}

/// Полноценный просмотрщик сторис (как в Telegram/Instagram)
/// Поддерживает фото + видео, прогресс-бары, автопереход, паузу, свайп.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  final List<StoryItem> stories;
  final int initialIndex;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  Timer? _progressTimer;
  double _progress = 0.0;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    if (widget.stories.isEmpty) {
      _currentIndex = 0;
      _pageController = PageController();
      return;
    }
    _currentIndex = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _startStory();
  }

  StoryItem get _currentStory => widget.stories[_currentIndex];

  void _startStory() {
    _progress = 0.0;
    _progressTimer?.cancel();
    final storyId = int.tryParse(_currentStory.id);
    if (storyId != null) {
      unawaited(StoryService.markViewed(storyId));
    }

    if (_currentStory.isVideo) {
      _initVideo();
    } else {
      _startPhotoTimer();
    }
  }

  Future<void> _initVideo() async {
    _videoController?.dispose();

    final url = ServerConfig.resolveMediaUrl(_currentStory.mediaUrl);
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));

    await _videoController!.initialize();
    await _videoController!.play();

    final duration = _videoController!.value.duration;
    _videoController!.addListener(_onVideoProgress);

    if (mounted) setState(() {});
  }

  void _onVideoProgress() {
    if (_videoController == null || _isPaused) return;

    final value = _videoController!.value;
    if (value.duration.inMilliseconds == 0) return;

    final progress = value.position.inMilliseconds / value.duration.inMilliseconds;

    setState(() {
      _progress = progress.clamp(0.0, 1.0);
    });

    if (progress >= 1.0) {
      _goToNext();
    }
  }

  void _startPhotoTimer() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _isPaused) return;

      setState(() {
        _progress += 50 / _currentStory.duration.inMilliseconds;
      });

      if (_progress >= 1.0) {
        timer.cancel();
        _goToNext();
      }
    });
  }

  void _pause() {
    setState(() => _isPaused = true);
    _progressTimer?.cancel();
    _videoController?.pause();
  }

  void _resume() {
    setState(() => _isPaused = false);
    if (_currentStory.isVideo) {
      _videoController?.play();
    } else {
      _startPhotoTimer();
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _progress = 0.0;
    });
    _videoController?.dispose();
    _videoController = null;
    _startStory();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Нет активных сторис',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          children: [
            // Основной контент
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final story = widget.stories[index];
                return _buildStoryContent(story);
              },
            ),

            // Прогресс-бары сверху
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(widget.stories.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < _currentIndex
                            ? 1.0
                            : (i == _currentIndex ? _progress : 0.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Автор
            if (_currentStory.authorName != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 16,
                child: Row(
                  children: [
                    if (_currentStory.authorAvatar != null)
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: CachedNetworkImageProvider(
                          ServerConfig.resolvePublisherAvatarUrl(_currentStory.authorAvatar!),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _currentStory.authorName!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

            // Кнопка закрытия
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Зоны тапа (лево/право)
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _goToPrevious,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _goToNext,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent(StoryItem story) {
    final url = ServerConfig.resolveMediaUrl(story.mediaUrl);

    if (story.isVideo) {
      return _videoController != null && _videoController!.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white));
    } else {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }
  }
}
