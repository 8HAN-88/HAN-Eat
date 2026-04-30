import 'package:chewie/chewie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/auth_service.dart';
import '../../../services/community_service.dart';
import '../../../services/server_config.dart';
import '../../../services/user_service.dart';
import '../presentation/enhanced_comments_page.dart';
import 'community_upload_screen.dart';

/// TikTok-style вертикальная лента с короткими видео (Reels)
class ReelsFeedScreen extends StatefulWidget {
  const ReelsFeedScreen({super.key});

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen> {
  final PageController _pageController = PageController();
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, ChewieController> _chewieControllers = {};
  final Map<String, bool> _isPaused = {}; // Состояние паузы для каждого видео
  int _currentIndex = 0;
  List<DocumentSnapshot> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _chewieControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVideos() async {
    try {
      // Проверяем, инициализирован ли Firebase
      try {
        Firebase.app();
      } catch (_) {
        // Firebase не инициализирован
        if (!mounted) return;
        setState(() {
          _videos = [];
          _isLoading = false;
        });
        return;
      }

      // Загружаем опубликованные видео, а также pending для тестирования
      // Сначала загружаем published, потом pending
      QuerySnapshot? publishedSnapshot;
      QuerySnapshot? pendingSnapshot;
      
      try {
        publishedSnapshot = await FirebaseFirestore.instance
            .collection('community_videos')
            .where('status', isEqualTo: 'published')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10), onTimeout: () {
              debugPrint('Timeout loading published videos');
              return FirebaseFirestore.instance
                  .collection('community_videos')
                  .limit(0)
                  .get();
            });
      } catch (e) {
        debugPrint('Error loading published videos: $e');
        publishedSnapshot = null;
      }
      
      try {
        pendingSnapshot = await FirebaseFirestore.instance
            .collection('community_videos')
            .where('status', isEqualTo: 'pending')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get()
            .timeout(const Duration(seconds: 10), onTimeout: () {
              debugPrint('Timeout loading pending videos');
              return FirebaseFirestore.instance
                  .collection('community_videos')
                  .limit(0)
                  .get();
            });
      } catch (e) {
        debugPrint('Error loading pending videos: $e');
        pendingSnapshot = null;
      }
      
      final allVideos = <DocumentSnapshot>[];
      if (publishedSnapshot != null) {
        allVideos.addAll(publishedSnapshot.docs);
      }
      if (pendingSnapshot != null) {
        allVideos.addAll(pendingSnapshot.docs);
      }
      
      // Сортируем по дате создания
      try {
        allVideos.sort((a, b) {
          try {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final aMs = aTime?.millisecondsSinceEpoch ?? 0;
            final bMs = bTime?.millisecondsSinceEpoch ?? 0;
            return bMs.compareTo(aMs);
          } catch (e) {
            debugPrint('Error sorting videos: $e');
            return 0;
          }
        });
      } catch (e) {
        debugPrint('Error in sort: $e');
      }

      if (!mounted) return;

      setState(() {
        _videos = allVideos;
        _isLoading = false;
      });

      // Загрузить первые несколько видео
      try {
        for (int i = 0; i < (_videos.length < 3 ? _videos.length : 3); i++) {
          _loadVideo(i);
        }
      } catch (e) {
        debugPrint('Error loading initial videos: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading videos: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _videos = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;

    final doc = _videos[index];
    final docId = doc.id;
    final data = doc.data() as Map<String, dynamic>;
    final videoUrl = data['url'] as String? ?? data['videoUrl'] as String?;

    if (videoUrl == null || _controllers.containsKey(docId)) return;
    final resolvedUrl = ServerConfig.resolveMediaUrl(videoUrl);

    try {
      final videoController = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
      );

      await videoController.initialize();
      if (!mounted) {
        videoController.dispose();
        return;
      }

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: index == 0, // Автовоспроизведение только для первого видео
        looping: true,
        allowFullScreen: false,
        showControls: false, // Скрываем стандартные контролы
        aspectRatio: videoController.value.aspectRatio,
        allowMuting: false, // Отключаем звук, как требовалось
        allowPlaybackSpeedChanging: false,
      );

      setState(() {
        _controllers[docId] = videoController;
        _chewieControllers[docId] = chewieController;
        _isPaused[docId] = false; // Инициализируем состояние паузы
      });
    } catch (e) {
      debugPrint('Error loading video $docId: $e');
    }
  }

  void _onPageChanged(int index) {
    // Остановить предыдущее видео
    if (_currentIndex < _videos.length) {
      final prevDocId = _videos[_currentIndex].id;
      _chewieControllers[prevDocId]?.pause();
      setState(() {
        _isPaused[prevDocId] = true; // Помечаем предыдущее как на паузе
      });
    }

    _currentIndex = index;

    // Загрузить видео вокруг текущего
    _loadVideo(index - 1);
    _loadVideo(index);
    _loadVideo(index + 1);

    // Воспроизвести текущее видео
    if (index < _videos.length) {
      final docId = _videos[index].id;
      setState(() {
        _isPaused[docId] = false; // Сбрасываем состояние паузы для текущего
      });
      _chewieControllers[docId]?.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _videos.isEmpty
              ? _buildEmptyState()
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: _onPageChanged,
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    return _buildVideoItem(index);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const CommunityUploadScreen(),
            ),
          );
          if (created == true && mounted) {
            _loadVideos();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Пока нет видео',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Будьте первым, кто загрузит Reel!',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(int index) {
    try {
      if (index < 0 || index >= _videos.length) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }

      final doc = _videos[index];
      final docId = doc.id;
      
      // Безопасное получение данных
      final docData = doc.data();
      if (docData == null || docData is! Map<String, dynamic>) {
        debugPrint('Invalid data for video $docId');
        return const Center(
          child: Text('Ошибка загрузки видео', style: TextStyle(color: Colors.white)),
        );
      }
      
      final data = docData as Map<String, dynamic>;
      final title = data['title'] as String? ?? 'Без названия';
      final description = data['description'] as String? ?? '';
      final authorId = data['uploaderId'] as String?;
      final authorName = data['author'] as String? ?? 'Неизвестный автор';

      final videoController = _controllers[docId];
      final chewieController = _chewieControllers[docId];
      final isPaused = _isPaused[docId] ?? false;

      return Stack(
        fit: StackFit.expand,
        children: [
          // Видео с обработкой тапа
          GestureDetector(
            onTap: () {
              if (chewieController != null) {
                setState(() {
                  _isPaused[docId] = !isPaused;
                });
                if (_isPaused[docId]!) {
                  chewieController.pause();
                } else {
                  chewieController.play();
                }
              }
            },
            behavior: HitTestBehavior.opaque,
            child: chewieController != null
                ? Chewie(controller: chewieController)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
          ),
          
          // Индикатор паузы (по центру экрана) - не блокирует тапы
          if (isPaused && chewieController != null)
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Icon(
                    Icons.pause_circle_filled,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
            ),
        // Градиент снизу (только для текста, не для кнопок)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 200,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),
        ),
        // UI элементы (Instagram Reels стиль)
        SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Нижняя часть с информацией (Instagram-стиль)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Левая часть: автор и описание
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Аватар и имя автора в одной строке
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white,
                                child: const Icon(Icons.person, size: 20, color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                authorName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (title.isNotEmpty) ...[
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Правая часть: кнопки действий (Instagram-стиль)
                    // Используем Material для лучшей видимости
                    Material(
                      color: Colors.transparent,
                      child: _VideoActionsColumn(
                        videoDocId: docId,
                        authorId: authorId ?? '',
                        authorName: authorName,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    } catch (e, stackTrace) {
      debugPrint('Error building video item at index $index: $e');
      debugPrint('Stack trace: $stackTrace');
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Ошибка загрузки видео',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }
  }
}

/// Колонка с действиями справа от видео (как в TikTok)
class _VideoActionsColumn extends StatelessWidget {
  const _VideoActionsColumn({
    required this.videoDocId,
    required this.authorId,
    required this.authorName,
  });

  final String videoDocId;
  final String authorId;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final currentUid = AuthService.instance.currentUser?.uid;

    // Instagram Reels стиль: компактные кнопки справа
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        // Добавляем легкий фон для лучшей видимости кнопок
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        // Лайк (Instagram-стиль)
        StreamBuilder<bool>(
          stream: CommunityService.isLikedStream(videoDocId, currentUid),
          builder: (context, snapshot) {
            final isLiked = snapshot.data ?? false;
            return StreamBuilder<int>(
              stream: CommunityService.likeCountStream(videoDocId),
              builder: (context, snapshot) {
                final likes = snapshot.data ?? 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.white,
                        size: 32,
                      ),
                      onPressed: () {
                        if (currentUid != null) {
                          CommunityService.toggleLike(videoDocId, currentUid);
                          HapticFeedback.lightImpact();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Войдите, чтобы лайкнуть')),
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCount(likes),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        // Комментарии (Instagram-стиль)
        StreamBuilder<int>(
          stream: CommunityService.commentsCountStream(videoDocId),
          builder: (context, snapshot) {
            final comments = snapshot.data ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.comment_outlined, color: Colors.white, size: 32),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EnhancedCommentsPage(videoDocId: videoDocId),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatCount(comments),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        // Репост (Instagram-стиль)
        StreamBuilder<bool>(
          stream: CommunityService.isRepostedStream(videoDocId, currentUid),
          builder: (context, snapshot) {
            final isReposted = snapshot.data ?? false;
            return StreamBuilder<int>(
              stream: CommunityService.repostCountStream(videoDocId),
              builder: (context, snapshot) {
                final reposts = snapshot.data ?? 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isReposted ? Icons.repeat : Icons.repeat_outlined,
                        color: isReposted ? Colors.green : Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        if (currentUid != null) {
                          CommunityService.toggleRepost(videoDocId, currentUid);
                          HapticFeedback.lightImpact();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Войдите, чтобы сделать репост')),
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCount(reposts),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        // Сохранение (Instagram-стиль)
        StreamBuilder<bool>(
          stream: CommunityService.isSavedStream(videoDocId, currentUid),
          builder: (context, snapshot) {
            final isSaved = snapshot.data ?? false;
            return StreamBuilder<int>(
              stream: CommunityService.saveCountStream(videoDocId),
              builder: (context, snapshot) {
                final saves = snapshot.data ?? 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? Colors.yellow : Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        if (currentUid != null) {
                          CommunityService.toggleSave(videoDocId, currentUid);
                          HapticFeedback.lightImpact();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Войдите, чтобы сохранить')),
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCount(saves),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        // Шаринг (Instagram-стиль)
        IconButton(
          icon: const Icon(Icons.share_outlined, color: Colors.white, size: 28),
          onPressed: () => _shareVideo(context, videoDocId, authorName),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(height: 20),
        // Репорт (Instagram-стиль)
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
          onPressed: () {
            _showReportDialog(context, videoDocId);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        ],
      ),
    );
  }

  Stream<bool> _isFollowingStream(String currentUid, String authorId) {
    try {
      // Проверяем, инициализирован ли Firebase
      Firebase.app();
      return FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .collection('followers')
          .doc(currentUid)
          .snapshots()
          .map((doc) => doc.exists)
          .handleError((error) {
            debugPrint('Error in _isFollowingStream: $error');
            return false;
          });
    } catch (_) {
      // Firebase не инициализирован, возвращаем Stream с false
      return Stream.value(false);
    }
  }

  void _showReportDialog(BuildContext context, String videoDocId) {
    final currentUid = AuthService.instance.currentUser?.uid;
    if (currentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы пожаловаться')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Пожаловаться на видео'),
        content: const Text('Вы уверены, что хотите пожаловаться на это видео?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await CommunityService.reportVideo(videoDocId, currentUid);
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Жалоба отправлена')),
                );
              }
            },
            child: const Text('Пожаловаться'),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }

  Future<void> _shareVideo(BuildContext context, String videoDocId, String authorName) async {
    try {
      // Проверяем, инициализирован ли Firebase
      try {
        Firebase.app();
      } catch (_) {
        // Firebase не инициализирован, используем базовую информацию
        if (context.mounted) {
          await Share.share(
            'Рилс от $authorName',
            subject: 'Рилс от $authorName',
          );
        }
        return;
      }

      // Получаем данные видео для шаринга
      final videoDoc = await FirebaseFirestore.instance
          .collection('community_videos')
          .doc(videoDocId)
          .get();
      
      if (!videoDoc.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Видео не найдено')),
          );
        }
        return;
      }

      final data = videoDoc.data() as Map<String, dynamic>;
      final title = data['title'] as String? ?? 'Рилс';
      final description = data['description'] as String? ?? '';
      final videoUrl = data['url'] as String? ?? data['videoUrl'] as String? ?? '';

      final shareText = description.isNotEmpty
          ? '$title\n\n$description\n\n$videoUrl'
          : '$title\n\n$videoUrl';

      await Share.share(
        shareText,
        subject: 'Рилс от $authorName',
      );
    } catch (e) {
      debugPrint('Error sharing video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при шаринге: $e')),
        );
      }
    }
  }
}

