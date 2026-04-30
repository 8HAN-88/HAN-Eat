// Экран Reels Feed с вертикальной прокруткой (как TikTok/Instagram Reels)
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/feed_service.dart';
import '../../../models/post_model.dart';
import 'package:go_router/go_router.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/number_formatter.dart';
import 'package:share_plus/share_plus.dart';

class ReelsFeedScreen extends ConsumerStatefulWidget {
  const ReelsFeedScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends ConsumerState<ReelsFeedScreen> {
  final PageController _pageController = PageController();
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, ChewieController> _chewieControllers = {};
  final Map<int, bool> _isPaused = {}; // Состояние паузы для каждого видео
  List<PostModel> _reels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _loadReels();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }
  
  void _disposeAllControllers() {
    for (var controller in _chewieControllers.values) {
      controller.dispose();
    }
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _chewieControllers.clear();
    _videoControllers.clear();
  }
  
  Future<void> _loadReels({bool refresh = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _reels = [];
        _nextCursor = null;
        _hasMore = true;
        _disposeAllControllers();
      }
    });
    
    try {
      final response = await FeedService.getFeed(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
        feedType: 'reels',
      );
      
      setState(() {
        if (refresh) {
          _reels = response.items;
        } else {
          _reels.addAll(response.items);
        }
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
      });
      
      // Инициализируем видео для первых 3 рилсов
      if (_reels.isNotEmpty) {
        _initializeVideos(0, math.min(3, _reels.length));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки рилсов: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _initializeVideos(int startIndex, int count) async {
    for (int i = startIndex; i < startIndex + count && i < _reels.length; i++) {
      final reel = _reels[i];
      if (_videoControllers.containsKey(i)) continue;
      
      // Получаем URL видео из body
      final videoUrl = _getVideoUrl(reel);
      if (videoUrl == null) continue;
      final resolvedUrl = ServerConfig.resolveMediaUrl(videoUrl);

      try {
        final videoController = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
        await videoController.initialize();
        
        if (!mounted) {
          videoController.dispose();
          return;
        }
        
        final chewieController = ChewieController(
          videoPlayerController: videoController,
          autoPlay: i == _currentIndex, // Автоплей только для текущего
          looping: true,
          allowFullScreen: false,
          showControls: false, // Скрываем стандартные контролы
          aspectRatio: videoController.value.aspectRatio,
          allowMuting: false, // Отключаем звук, как требовалось
          allowPlaybackSpeedChanging: false,
        );
        
        setState(() {
          _videoControllers[i] = videoController;
          _chewieControllers[i] = chewieController;
        });
      } catch (e) {
        debugPrint('Ошибка инициализации видео $i: $e');
      }
    }
  }
  
  String? _getVideoUrl(PostModel post) {
    final body = post.body;
    if (body == null) return null;
    
    final media = body['media'] as List<dynamic>?;
    if (media == null || media.isEmpty) return null;
    
    final video = media.firstWhere(
      (m) => m['type'] == 'video',
      orElse: () => null,
    );
    
    return video?['url'] as String?;
  }
  
  void _onPageChanged(int index) {
    // Останавливаем предыдущее видео
    if (_currentIndex < _chewieControllers.length) {
      _chewieControllers[_currentIndex]?.pause();
      setState(() {
        _isPaused[_currentIndex] = true; // Помечаем предыдущее как на паузе
      });
    }
    
    setState(() {
      _currentIndex = index;
      _isPaused[index] = false; // Сбрасываем состояние паузы для текущего
    });
    
    // Воспроизводим текущее видео
    if (_chewieControllers.containsKey(index)) {
      _chewieControllers[index]?.play();
    } else {
      // Инициализируем видео, если еще не инициализировано
      _initializeVideos(index, 1).then((_) {
        if (mounted && _chewieControllers.containsKey(index)) {
          _chewieControllers[index]?.play();
        }
      });
    }
    
    // Загружаем больше, если приближаемся к концу
    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadReels();
    }
    
    // Предзагружаем следующие видео
    if (index + 1 < _reels.length) {
      _initializeVideos(index + 1, 2);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_reels.isEmpty && _isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_reels.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Рилсы'),
        ),
        body: const Center(child: Text('Нет рилсов')),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length + (_hasMore ? 1 : 0),
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          if (index == _reels.length) {
            // Индикатор загрузки в конце
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          
          final reel = _reels[index];
          return ReelCard(
            reel: reel,
            index: index,
            videoController: _chewieControllers[index],
            isCurrent: index == _currentIndex,
            isPaused: _isPaused[index] ?? false,
            onPauseToggle: (paused) {
              setState(() {
                _isPaused[index] = paused;
              });
            },
            onLike: () => _toggleLike(reel),
            onComment: () {
              context.push('/post/${reel.id}/comments');
            },
            onShare: () => _shareReel(reel),
            onSave: () => _toggleSave(reel),
            onRepost: () => _toggleRepost(reel),
            onAuthorTap: () {
              context.push('/profile?userId=${reel.userId}');
            },
          );
        },
      ),
    );
  }
  
  Future<void> _toggleLike(PostModel reel) async {
    try {
      final response = await LikeService.likePost(reel.id);
      setState(() {
        // Обновляем счетчик лайков
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = PostModel(
            id: _reels[index].id,
            type: _reels[index].type,
            title: _reels[index].title,
            description: _reels[index].description,
            status: _reels[index].status,
            createdAt: _reels[index].createdAt,
            publishedAt: _reels[index].publishedAt,
            userId: _reels[index].userId,
            communityId: _reels[index].communityId,
            body: _reels[index].body,
            tags: _reels[index].tags,
            likesCount: response.likesCount,
            commentsCount: _reels[index].commentsCount,
            repostsCount: _reels[index].repostsCount,
            viewsCount: _reels[index].viewsCount,
            isLiked: !_reels[index].isLiked,
            isSaved: _reels[index].isSaved,
            isReposted: _reels[index].isReposted,
            author: _reels[index].author,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  Future<void> _toggleSave(PostModel reel) async {
    try {
      final isSaved = reel.isSaved ?? false;
      if (isSaved) {
        await SavedPostsService.unsavePost(reel.id.toString());
      } else {
        await SavedPostsService.savePost(reel.id.toString());
      }
      setState(() {
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = PostModel(
            id: _reels[index].id,
            type: _reels[index].type,
            title: _reels[index].title,
            description: _reels[index].description,
            status: _reels[index].status,
            createdAt: _reels[index].createdAt,
            publishedAt: _reels[index].publishedAt,
            userId: _reels[index].userId,
            communityId: _reels[index].communityId,
            body: _reels[index].body,
            tags: _reels[index].tags,
            likesCount: _reels[index].likesCount,
            commentsCount: _reels[index].commentsCount,
            repostsCount: _reels[index].repostsCount,
            viewsCount: _reels[index].viewsCount,
            isLiked: _reels[index].isLiked,
            isSaved: !isSaved,
            isReposted: _reels[index].isReposted,
            author: _reels[index].author,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  Future<void> _toggleRepost(PostModel reel) async {
    try {
      final isReposted = reel.isReposted ?? false;
      if (isReposted) {
        await RepostService.unrepost(reel.id.toString());
      } else {
        await RepostService.repost(reel.id.toString());
      }
      setState(() {
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = PostModel(
            id: _reels[index].id,
            type: _reels[index].type,
            title: _reels[index].title,
            description: _reels[index].description,
            status: _reels[index].status,
            createdAt: _reels[index].createdAt,
            publishedAt: _reels[index].publishedAt,
            userId: _reels[index].userId,
            communityId: _reels[index].communityId,
            body: _reels[index].body,
            tags: _reels[index].tags,
            likesCount: _reels[index].likesCount,
            commentsCount: _reels[index].commentsCount,
            repostsCount: _reels[index].repostsCount,
            viewsCount: _reels[index].viewsCount,
            isLiked: _reels[index].isLiked,
            isSaved: _reels[index].isSaved,
            isReposted: !isReposted,
            author: _reels[index].author,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final text = msg.contains('own post') || msg.contains('свой пост')
            ? 'Нельзя репостнуть свой пост'
            : 'Ошибка: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _shareReel(PostModel reel) async {
    try {
      final videoUrl = _getVideoUrl(reel);
      final text = reel.description ?? 'Посмотрите этот рилс!';
      final fullText = '$text\n${videoUrl ?? ''}';
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: fullText));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
          );
        }
        return;
      }
      await Share.share(fullText, subject: reel.title);
    } catch (e) {
      if (mounted) {
        try {
          final videoUrl = _getVideoUrl(reel);
          final text = reel.description ?? 'Посмотрите этот рилс!';
          final fullText = '$text\n${videoUrl ?? ''}';
          await Clipboard.setData(ClipboardData(text: fullText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
          );
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при шаринге: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class ReelCard extends StatefulWidget {
  final PostModel reel;
  final int index;
  final ChewieController? videoController;
  final bool isCurrent;
  final bool isPaused;
  final ValueChanged<bool> onPauseToggle;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onRepost;
  final VoidCallback onAuthorTap;
  
  const ReelCard({
    Key? key,
    required this.reel,
    required this.index,
    this.videoController,
    required this.isCurrent,
    required this.isPaused,
    required this.onPauseToggle,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onRepost,
    required this.onAuthorTap,
  }) : super(key: key);

  @override
  State<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<ReelCard> with SingleTickerProviderStateMixin {
  DateTime? _lastTap;
  bool _showLikeAnimation = false;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;
  late Animation<double> _likeOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 0.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _likeOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: const Interval(0.5, 1.0),
      ),
    );
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (!widget.reel.isLiked) {
      widget.onLike();
      setState(() {
        _showLikeAnimation = true;
      });
      _likeAnimationController.forward().then((_) {
        if (mounted) {
          setState(() {
            _showLikeAnimation = false;
          });
          _likeAnimationController.reset();
        }
      });
    }
  }

  void _handleSingleTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 300)) {
      _handleDoubleTap();
      _lastTap = null;
    } else {
      _lastTap = now;
      // Тап на экран для паузы/плей (без задержки для более отзывчивого интерфейса)
      if (widget.videoController != null) {
        final newPausedState = !widget.isPaused;
        widget.onPauseToggle(newPausedState);
        if (newPausedState) {
          widget.videoController!.pause();
        } else {
          widget.videoController!.play();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.reel.author;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return GestureDetector(
      onTap: _handleSingleTap,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Видео (полноэкранное)
          if (widget.videoController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: widget.videoController!.videoPlayerController.value.size.width,
                  height: widget.videoController!.videoPlayerController.value.size.height,
                  child: Chewie(controller: widget.videoController!),
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          
          // Индикатор паузы
          if (widget.isPaused)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Icon(
                  Icons.pause_circle_filled,
                  color: Colors.white,
                  size: 80,
                ),
              ),
            ),
          
          // Прозрачный overlay для паузы/плей (не закрываем правую колонку — 100px)
          Positioned(
            left: 0,
            top: 0,
            right: 100,
            bottom: 0,
            child: GestureDetector(
              onTap: _handleSingleTap,
              onDoubleTap: _handleDoubleTap,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          
          // Анимация лайка при двойном тапе
          if (_showLikeAnimation)
            Center(
              child: AnimatedBuilder(
                animation: _likeAnimationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _likeOpacityAnimation.value,
                    child: Transform.scale(
                      scale: _likeScaleAnimation.value,
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 100,
                      ),
                    ),
                  );
                },
              ),
            ),
          
          // Градиент снизу (для читаемости текста)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Контент справа (кнопки) — оборачиваем в Material для надёжного hit-testing на web
          Positioned(
            right: 12,
            bottom: 100,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Аватар автора (сверху)
                GestureDetector(
                  onTap: widget.onAuthorTap,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: ClipOval(
                      child: author?.avatarUrl != null
                          ? CachedNetworkImage(
                              imageUrl: author!.avatarUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[800],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.person, color: Colors.white),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: Center(
                                child: Text(
                                  author?.name.isNotEmpty == true
                                      ? author!.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Лайк
                _ActionButton(
                  icon: widget.reel.isLiked ? Icons.favorite : Icons.favorite_border,
                  count: widget.reel.likesCount,
                  onTap: widget.onLike,
                  color: widget.reel.isLiked ? Colors.red : Colors.white,
                ),
                const SizedBox(height: 20),
                
                // Комментарий
                _ActionButton(
                  icon: Icons.comment_outlined,
                  count: widget.reel.commentsCount,
                  onTap: widget.onComment,
                ),
                const SizedBox(height: 20),
                
                // Репост
                _ActionButton(
                  icon: widget.reel.isReposted ?? false
                      ? Icons.repeat
                      : Icons.repeat_outlined,
                  count: widget.reel.repostsCount,
                  onTap: widget.onRepost,
                  color: (widget.reel.isReposted ?? false) ? Colors.green : Colors.white,
                ),
                const SizedBox(height: 20),
                
                // Сохранить
                _ActionButton(
                  icon: (widget.reel.isSaved ?? false)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  count: 0,
                  onTap: widget.onSave,
                  color: (widget.reel.isSaved ?? false) ? Colors.amber : Colors.white,
                ),
                const SizedBox(height: 20),
                
                // Поделиться
                _ActionButton(
                  icon: Icons.share_outlined,
                  count: 0,
                  onTap: widget.onShare,
                ),
              ],
            ),
            ),
          ),
          
          // Информация об авторе и описание снизу слева - как в Instagram
          Positioned(
            bottom: 0,
            left: 12,
            right: 80,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Имя автора (кликабельное)
                  GestureDetector(
                    onTap: widget.onAuthorTap,
                    child: Text(
                      '@${author?.username ?? author?.name ?? "unknown"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Описание с поддержкой хештегов и упоминаний
                  if (widget.reel.description != null && widget.reel.description!.isNotEmpty)
                    _buildDescription(widget.reel.description!),
                  
                  // Хештеги из tags
                  if (widget.reel.tags != null && widget.reel.tags!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: widget.reel.tags!.map((tag) {
                        return GestureDetector(
                          onTap: () {
                            // TODO: Переход к поиску по хештегу
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Поиск по хештегу: #$tag')),
                            );
                          },
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(String description) {
    // Простая обработка хештегов и упоминаний
    final words = description.split(' ');
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.4,
        ),
        children: words.map((word) {
          if (word.startsWith('#')) {
            return TextSpan(
              text: '$word ',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  // TODO: Переход к поиску по хештегу
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Поиск по хештегу: $word')),
                  );
                },
            );
          } else if (word.startsWith('@')) {
            return TextSpan(
              text: '$word ',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  // TODO: Переход к профилю пользователя
                  final username = word.substring(1);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Профиль: @$username')),
                  );
                },
            );
          } else {
            return TextSpan(text: '$word ');
          }
        }).toList(),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? color;
  
  const _ActionButton({
    Key? key,
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
  }) : super(key: key);
  
  // Используем утилиту для форматирования чисел
  String _formatCount(int count) => NumberFormatter.formatCount(count);
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              color: color ?? Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatCount(count),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

