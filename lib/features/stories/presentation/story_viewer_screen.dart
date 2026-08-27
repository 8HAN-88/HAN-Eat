import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'package:uuid/uuid.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/video_player_helper.dart';
import '../../chat/application/chat_open_direct.dart';
import '../../chat/application/chat_ready_outgoing.dart';
import '../../chat/presentation/widgets/chat_story_reply_bubble.dart';
import '../data/story_models.dart';
import '../data/story_service.dart';

/// Один элемент сторис
class StoryItem {
  StoryItem({
    required this.id,
    required this.mediaUrl,
    required this.authorId,
    this.authorName,
    this.authorAvatar,
    this.thumbnailUrl,
    this.duration = const Duration(seconds: 5),
    this.isVideo = false,
    this.viewsCount = 0,
    this.myReaction,
    this.reactions = const [],
  });

  final String id;
  final String mediaUrl;
  final int authorId;
  final String? authorName;
  final String? authorAvatar;
  final String? thumbnailUrl;
  final Duration duration;
  final bool isVideo;
  int viewsCount;
  String? myReaction;
  List<StoryReactionSummary> reactions;

  bool get isOwn {
    final me = AuthService.instance.currentUser;
    return me != null && me.id == authorId;
  }
}

/// Полноценный просмотрщик сторис (как в Telegram/Instagram)
/// Поддерживает фото + видео, прогресс-бары, автопереход, паузу, свайп,
/// реакции и список просмотров для своих сторис.
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
  static const _quickReactions = ['👍', '❤️', '😂', '🔥', '😮', '😢'];

  late PageController _pageController;
  late int _currentIndex;
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  VideoPlayerController? _videoController;
  Timer? _progressTimer;
  double _progress = 0.0;
  bool _isPaused = false;
  bool _reacting = false;
  bool _replySending = false;

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
    if (storyId != null && !_currentStory.isOwn) {
      unawaited(_markViewed(storyId));
    }

    if (_currentStory.isVideo) {
      _initVideo();
    } else {
      _startPhotoTimer();
    }
  }

  Future<void> _markViewed(int storyId) async {
    try {
      final updated = await StoryService.markViewed(storyId);
      if (!mounted) return;
      final idx = widget.stories.indexWhere((s) => s.id == '$storyId');
      if (idx < 0) return;
      setState(() {
        widget.stories[idx].viewsCount = updated.viewsCount;
        widget.stories[idx].myReaction = updated.myReaction;
        widget.stories[idx].reactions = updated.reactions;
      });
    } catch (_) {}
  }

  Future<void> _initVideo() async {
    _videoController?.dispose();
    _videoController = null;

    final url = ServerConfig.resolveMediaUrl(_currentStory.mediaUrl);
    try {
      final controller = await VideoPlayerHelper.createPreparedController(
        url,
        loop: false,
        muted: kIsWeb,
        autoPlay: false,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _videoController = controller;
      controller.addListener(_onVideoProgress);
      await VideoPlayerHelper.ensurePlaying(
        controller,
        shouldContinue: () => mounted && !_isPaused,
      );
      if (kIsWeb && controller.value.isPlaying) {
        try {
          await controller.setVolume(1);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Safari/сеть: не зависаем на чёрном кадре — идём дальше как фото.
      if (mounted) _startPhotoTimer();
    }
  }

  void _onVideoProgress() {
    if (_videoController == null || _isPaused) return;

    final value = _videoController!.value;
    if (value.duration.inMilliseconds == 0) return;

    final progress =
        value.position.inMilliseconds / value.duration.inMilliseconds;

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
      final controller = _videoController;
      if (controller != null) {
        unawaited(
          VideoPlayerHelper.ensurePlaying(
            controller,
            shouldContinue: () => mounted && !_isPaused,
          ),
        );
      }
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

  Future<void> _react(String emoji) async {
    if (_reacting || _currentStory.isOwn) return;
    final storyId = int.tryParse(_currentStory.id);
    if (storyId == null) return;
    setState(() => _reacting = true);
    _pause();
    try {
      final updated = await StoryService.setReaction(
        storyId: storyId,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        _currentStory.myReaction = updated.myReaction;
        _currentStory.reactions = updated.reactions;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить реакцию')),
      );
    } finally {
      if (mounted) {
        setState(() => _reacting = false);
        _resume();
      }
    }
  }

  Future<void> _openViewers() async {
    if (!_currentStory.isOwn) return;
    final storyId = int.tryParse(_currentStory.id);
    if (storyId == null) return;
    _pause();
    try {
      final page = await StoryService.fetchViewers(storyId);
      if (!mounted) return;
      setState(() => _currentStory.viewsCount = page.viewsCount);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.grey.shade900,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Просмотры · ${page.viewsCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (page.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Пока никто не посмотрел',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, index) {
                          final item = page.items[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundImage: item.user.avatarUrl == null
                                  ? null
                                  : CachedNetworkImageProvider(
                                      ServerConfig.resolvePublisherAvatarUrl(
                                        item.user.avatarUrl!,
                                      ),
                                    ),
                              child: item.user.avatarUrl == null
                                  ? Text(
                                      item.user.name.isNotEmpty
                                          ? item.user.name[0].toUpperCase()
                                          : '?',
                                    )
                                  : null,
                            ),
                            title: Text(
                              item.user.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              _formatViewedAt(item.viewedAt),
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: item.reaction == null
                                ? null
                                : Text(
                                    item.reaction!,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить просмотры')),
      );
    } finally {
      if (mounted) _resume();
    }
  }

  String _formatViewedAt(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _sendStoryReply() async {
    if (_replySending || _currentStory.isOwn) return;
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final storyId = int.tryParse(_currentStory.id);
    if (storyId == null) return;

    setState(() => _replySending = true);
    _pause();
    try {
      final opened = await ChatOpenDirect.openNow(
        _currentStory.authorId,
        peer: ChatUserBrief(
          id: _currentStory.authorId,
          name: _currentStory.authorName,
          avatarUrl: _currentStory.authorAvatar,
        ),
      );
      final payload = ChatStoryReplyPayload(
        storyId: storyId,
        text: text,
        authorId: _currentStory.authorId,
        authorName: _currentStory.authorName,
        mediaUrl: _currentStory.mediaUrl,
        mediaType: _currentStory.isVideo ? 'video' : 'image',
        thumbnailUrl: _currentStory.thumbnailUrl,
      );
      final pending = ChatReadyOutgoing(
        tempId: newReadyOutgoingTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'story_reply',
        content: payload.encode(),
        mediaUrl: _currentStory.thumbnailUrl ?? _currentStory.mediaUrl,
      );
      final uid = AuthService.instance.currentUser?.id ?? 0;
      Future<void> persistTo(int conversationId) {
        return persistReadyOutgoing(
          conversationId: conversationId,
          pending: pending,
          optimistic: ChatMessage(
            id: pending.tempId,
            conversationId: conversationId,
            senderId: uid,
            type: 'story_reply',
            content: pending.content,
            mediaUrl: pending.mediaUrl,
            createdAt: DateTime.now(),
            isMine: true,
            clientMessageId: pending.clientMessageId,
          ),
        );
      }

      if (opened.id > 0) {
        await persistTo(opened.id);
      } else {
        unawaited(() async {
          final real = await ChatOpenDirect.resolve(_currentStory.authorId);
          await persistTo(real.id);
        }());
      }
      if (!mounted) return;
      _replyController.clear();
      _replyFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ответ отправлен в личные сообщения')),
      );
      Navigator.of(context).pop();
      if (!mounted) return;
      context.push(ChatThreadRoute.pathFor(opened), extra: opened);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось отправить ответ'),
          ),
        ),
      );
      _resume();
    } finally {
      if (mounted) setState(() => _replySending = false);
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoController?.dispose();
    _pageController.dispose();
    _replyController.dispose();
    _replyFocus.dispose();
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

    final story = _currentStory;
    final reactionLabel = story.reactions.isEmpty
        ? null
        : story.reactions.map((r) => '${r.emoji}${r.count}').join(' ');

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final item = widget.stories[index];
                return _buildStoryContent(item);
              },
            ),
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
            if (story.authorName != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 16,
                right: 56,
                child: Row(
                  children: [
                    if (story.authorAvatar != null)
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: CachedNetworkImageProvider(
                          ServerConfig.resolvePublisherAvatarUrl(
                            story.authorAvatar!,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        story.authorName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (reactionLabel != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        reactionLabel,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
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
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: story.isOwn
                  ? Center(
                      child: TextButton.icon(
                        onPressed: _openViewers,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: Text(
                          story.viewsCount == 0
                              ? 'Нет просмотров'
                              : '${story.viewsCount} просмотр${_ruPlural(story.viewsCount)}',
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final emoji in _quickReactions)
                              InkWell(
                                onTap: _reacting ? null : () => _react(emoji),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: story.myReaction == emoji
                                        ? Colors.white24
                                        : Colors.black38,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                focusNode: _replyFocus,
                                enabled: !_replySending,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white,
                                textInputAction: TextInputAction.send,
                                onTap: _pause,
                                onSubmitted: (_) => unawaited(_sendStoryReply()),
                                decoration: InputDecoration(
                                  hintText: 'Ответить…',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                  filled: true,
                                  fillColor: Colors.black45,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed:
                                  _replySending ? null : () => unawaited(_sendStoryReply()),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white24,
                                foregroundColor: Colors.white,
                              ),
                              icon: _replySending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _ruPlural(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'а';
    return 'ов';
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
        placeholder: (_, __) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }
  }
}
