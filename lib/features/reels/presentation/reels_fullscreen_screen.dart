// Fullscreen Reels при тапе на видео в ленте — вертикальный свайп, возврат на то же место
import 'dart:math' as math;
import '../../../utils/api_error_parser.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../models/post_model.dart';
import '../../../services/feed_service.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/server_config.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../app/app_router.dart';
import 'reels_feed_screen.dart';

class ReelsFullscreenScreen extends StatefulWidget {
  final PostModel initialPost;

  const ReelsFullscreenScreen({
    super.key,
    required this.initialPost,
  });

  @override
  State<ReelsFullscreenScreen> createState() => _ReelsFullscreenScreenState();
}

class _ReelsFullscreenScreenState extends State<ReelsFullscreenScreen> {
  late PageController _pageController;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, ChewieController> _chewieControllers = {};
  final Map<int, bool> _isPaused = {};
  List<PostModel> _reels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _reels = [widget.initialPost];
    _loadMoreReels();
    _initializeVideos(0, 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (var c in _chewieControllers.values) {
      c.dispose();
    }
    for (var c in _videoControllers.values) {
      c.dispose();
    }
    _chewieControllers.clear();
    _videoControllers.clear();
  }

  Future<void> _loadMoreReels() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await FeedService.getFeed(
        cursor: _nextCursor,
        limit: 20,
        feedType: 'reels',
      );

      if (!mounted) return;

      final existingIds = _reels.map((r) => r.id).toSet();
      final newReels = response.items.where((r) => !existingIds.contains(r.id)).toList();

      setState(() {
        _reels.addAll(newReels);
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _isLoading = false;
      });

      if (newReels.isNotEmpty) {
        _initializeVideos(1, math.min(3, _reels.length));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initializeVideos(int startIndex, int count) async {
    for (int i = startIndex; i < startIndex + count && i < _reels.length; i++) {
      if (_videoControllers.containsKey(i)) continue;

      final reel = _reels[i];
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
          autoPlay: i == _currentIndex,
          looping: true,
          allowFullScreen: false,
          showControls: false,
          aspectRatio: videoController.value.aspectRatio,
          allowMuting: false,
          allowPlaybackSpeedChanging: false,
        );

        setState(() {
          _videoControllers[i] = videoController;
          _chewieControllers[i] = chewieController;
        });
      } catch (e) {
        debugPrint('ReelsFullscreen init video $i: $e');
      }
    }
  }

  String? _getVideoUrl(PostModel post) {
    final body = post.body;
    if (body == null) return null;

    final media = body['media'] as List<dynamic>?;
    if (media == null || media.isEmpty) return null;

    for (final m in media) {
      if (m is Map<String, dynamic> && m['type'] == 'video') {
        return m['url'] as String?;
      }
    }
    return null;
  }

  void _onPageChanged(int index) {
    if (_currentIndex < _chewieControllers.length) {
      _chewieControllers[_currentIndex]?.pause();
      setState(() => _isPaused[_currentIndex] = true);
    }

    setState(() {
      _currentIndex = index;
      _isPaused[index] = false;
    });

    if (_chewieControllers.containsKey(index)) {
      _chewieControllers[index]?.play();
    } else {
      _initializeVideos(index, 1).then((_) {
        if (mounted && _chewieControllers.containsKey(index)) {
          _chewieControllers[index]?.play();
        }
      });
    }

    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadMoreReels();
    }
    if (index + 1 < _reels.length) {
      _initializeVideos(index + 1, 2);
    }
  }

  Future<void> _toggleLike(PostModel reel) async {
    try {
      final response = await LikeService.likePost(reel.id);
      _updateReelAt(reel.id, (r) => _copyReelWith(r, likesCount: response.likesCount, isLiked: !r.isLiked));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userVisibleError(e))));
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
      _updateReelAt(reel.id, (r) => _copyReelWith(r, isSaved: !isSaved));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userVisibleError(e))));
      }
    }
  }

  Future<void> _toggleRepost(PostModel reel) async {
    if (!mounted) return;
    try {
      final isReposted = reel.isReposted ?? false;
      if (isReposted) {
        await RepostService.unrepost(reel.id.toString());
      } else {
        await RepostService.repost(reel.id.toString());
      }
      if (mounted) {
        _updateReelAt(reel.id, (r) => _copyReelWith(r, isReposted: !isReposted));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isReposted ? 'Репост отменён' : 'Репост выполнен')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final text = msg.contains('own post') || msg.contains('свой пост')
            ? 'Нельзя репостнуть свой пост'
            : userVisibleAuthError(
                e,
                fallback: 'Не удалось сделать репост',
                authFallback: 'Войдите, чтобы сделать репост',
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
    }
  }

  PostModel _copyReelWith(
    PostModel r, {
    int? likesCount,
    bool? isLiked,
    bool? isSaved,
    bool? isReposted,
  }) {
    return PostModel(
      id: r.id,
      type: r.type,
      title: r.title,
      description: r.description,
      status: r.status,
      createdAt: r.createdAt,
      publishedAt: r.publishedAt,
      userId: r.userId,
      communityId: r.communityId,
      body: r.body,
      tags: r.tags,
      likesCount: likesCount ?? r.likesCount,
      commentsCount: r.commentsCount,
      repostsCount: r.repostsCount,
      viewsCount: r.viewsCount,
      isPromoted: r.isPromoted,
      isLiked: isLiked ?? r.isLiked,
      isSaved: isSaved ?? r.isSaved,
      isReposted: isReposted ?? r.isReposted,
      author: r.author,
      repostedBy: r.repostedBy,
      channel: r.channel,
    );
  }

  void _updateReelAt(int id, PostModel Function(PostModel) updater) {
    final idx = _reels.indexWhere((r) => r.id == id);
    if (idx != -1 && mounted) {
      setState(() {
        _reels[idx] = updater(_reels[idx]);
      });
    }
  }

  Future<void> _shareReel(PostModel reel) async {
    if (!mounted) return;
    await ShareActionSheet.showForReel(
      context,
      reel: reel,
      onRepostToWall: () => _toggleRepost(reel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _reels.length + (_hasMore ? 1 : 0),
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              if (index == _reels.length) {
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
                  setState(() => _isPaused[index] = paused);
                },
                onLike: () => _toggleLike(reel),
                onComment: () => context.push('/post/${reel.id}/comments'),
                onShare: () => _shareReel(reel),
                onSave: () => _toggleSave(reel),
                onRepost: () => _toggleRepost(reel),
                onAuthorTap: () => context.push('/profile?userId=${reel.userId}'),
                onHashtagTap: (tag) {
                  final q = tag.startsWith('#') ? tag : '#$tag';
                  context.push(
                    '${SearchRoute.path}?q=${Uri.encodeQueryComponent(q)}',
                  );
                },
                onMentionTap: (username, r) {
                  final uname = username.trim();
                  if (uname.isEmpty) return;
                  final author = r.author;
                  if (author?.username != null &&
                      author!.username!.toLowerCase() == uname.toLowerCase()) {
                    context.push('${ProfileRoute.path}?userId=${r.userId}');
                  } else {
                    context.push(
                      '${SearchRoute.path}?q=${Uri.encodeQueryComponent('@$uname')}',
                    );
                  }
                },
                onReport: () => reportPostWithDialog(context, reel.id),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
