import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/open_app_link.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';
import '../services/saved_posts_service.dart';
import '../services/server_config.dart';
import '../utils/post_publisher_display.dart';
import '../utils/session_snackbar.dart';
import '../utils/shared_post_media.dart';
import 'app_avatar.dart';
import 'share_action_sheet.dart';

class _ReelPostCache {
  static final Map<int, PostModel> posts = {};
  static final Map<int, Future<PostModel?>> inflight = {};

  static Future<PostModel?> fetch(int id) {
    final cached = posts[id];
    if (cached != null) return Future.value(cached);
    final pending = inflight[id];
    if (pending != null) return pending;
    final future = ApiService.getPostById(id);
    inflight[id] = future;
    return future.then((post) {
      if (post != null) posts[id] = post;
      return post;
    }).whenComplete(() => inflight.remove(id));
  }

  static void remember(PostModel post) {
    posts[post.id] = post;
  }
}

enum SharedPostCardPlace { chat, feed, preview }

/// Instagram DM shared-post card: media, author overlay, play, share/save.
class SharedPostCard extends StatefulWidget {
  const SharedPostCard({
    super.key,
    required this.postId,
    required this.url,
    this.mine = true,
    this.compact = false,
    this.showActions = true,
    this.place = SharedPostCardPlace.chat,
    this.initialPost,
    this.onDoubleTap,
  });

  final int postId;
  final String url;
  final bool mine;
  final bool compact;
  final bool showActions;
  final SharedPostCardPlace place;
  final PostModel? initialPost;
  final VoidCallback? onDoubleTap;

  @override
  State<SharedPostCard> createState() => _SharedPostCardState();
}

/// Backward-compatible alias used by older chat call sites.
class ChatReelPreview extends SharedPostCard {
  const ChatReelPreview({
    super.key,
    required super.postId,
    required super.url,
    super.mine = true,
    super.compact = false,
    super.showActions = true,
  });
}

class _SharedPostCardState extends State<SharedPostCard> {
  PostModel? _post;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialPost;
    if (seeded != null && seeded.id == widget.postId) {
      _ReelPostCache.remember(seeded);
    }
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SharedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      unawaited(_load());
      return;
    }
    final seeded = widget.initialPost;
    if (seeded != null && seeded.id == widget.postId && !identical(seeded, _post)) {
      _ReelPostCache.remember(seeded);
      setState(() => _post = seeded);
    }
  }

  Future<void> _load() async {
    final seeded = widget.initialPost;
    final cached = _ReelPostCache.posts[widget.postId] ??
        (seeded != null && seeded.id == widget.postId ? seeded : null);
    setState(() {
      _loading = cached == null;
      _loadFailed = false;
      _post = cached;
    });
    try {
      final post = await _ReelPostCache.fetch(widget.postId);
      var saved = post?.isSaved ?? false;
      if (post != null) {
        try {
          saved = await SavedPostsService.isPostSaved(post.id);
        } catch (_) {}
      }
      if (!mounted || widget.postId != (post?.id ?? widget.postId)) return;
      setState(() {
        _post = post ?? cached;
        _saved = saved;
        _loading = false;
        _loadFailed = post == null && cached == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = _post == null;
      });
    }
  }

  Future<void> _open() async {
    await openAppOrExternalLink(context, widget.url);
  }

  Future<void> _share() async {
    final post = _post;
    if (post == null) return;
    if (post.type == 'reel' || SharedPostMedia.isVideo(post)) {
      await ShareActionSheet.showForReel(context, reel: post);
    } else {
      await ShareActionSheet.showForPost(context, post: post);
    }
  }

  Future<void> _toggleSave() async {
    if (_saving || _post == null) return;
    setState(() => _saving = true);
    final next = !_saved;
    try {
      if (next) {
        await SavedPostsService.savePostById(_post!.id);
      } else {
        await SavedPostsService.unsavePostById(_post!.id);
      }
      if (!mounted) return;
      setState(() {
        _saved = next;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(
        context,
        e,
        fallback: 'Не удалось сохранить',
        onRetry: () => unawaited(_toggleSave()),
      );
    }
  }

  bool get _isVideo {
    final post = _post;
    if (post == null) return widget.url.contains('/reel/');
    return SharedPostMedia.isVideo(post);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _compactCard(context);
    }
    return _igCard(context);
  }

  Widget _compactCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = _post;
    final name = post == null ? 'Пост' : PostPublisherDisplay.label(post);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 9 / 12,
                child: _poster(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isVideo ? 'Рилс' : 'Пост',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.play_circle_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _igCard(BuildContext context) {
    final feed = widget.place == SharedPostCardPlace.feed;
    final preview = widget.place == SharedPostCardPlace.preview;
    final video = _isVideo;
    final screenW = MediaQuery.sizeOf(context).width;
    final width = feed
        ? double.infinity
        : preview
            ? (video ? 148.0 : 164.0)
            : (screenW * (video ? 0.54 : 0.62)).clamp(176.0, video ? 228.0 : 268.0);
    final aspect = video ? (9 / 16) : (4 / 5);
    final radius = feed ? 16.0 : 18.0;
    final post = _post;
    final name = post == null ? 'HanWe' : PostPublisherDisplay.label(post);
    final avatar = post == null ? null : PostPublisherDisplay.avatarUrl(post);
    final caption = post == null ? null : SharedPostMedia.caption(post);
    final showFooter = !video &&
        widget.place == SharedPostCardPlace.chat &&
        (name.isNotEmpty || (caption != null && caption.isNotEmpty));

    final media = _mediaStack(
      name: name,
      avatar: avatar,
      video: video,
    );

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(aspectRatio: aspect, child: media),
        if (showFooter) _photoFooter(name: name, caption: caption),
      ],
    );

    final clipped = Material(
      color: const Color(0xFF111111),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        onDoubleTap: widget.onDoubleTap,
        child: card,
      ),
    );

    if (feed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: clipped,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(width: width, child: clipped),
    );
  }

  Widget _mediaStack({
    required String name,
    required String? avatar,
    required bool video,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _poster(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Color(0x99000000), Color(0x00000000)],
            ),
          ),
        ),
        if (_loading)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          )
        else if (_loadFailed)
          Center(
            child: TextButton(
              onPressed: () => unawaited(_load()),
              child: const Text(
                'Повторить',
                style: TextStyle(color: Colors.white),
              ),
            ),
          )
        else if (video)
          Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 36,
              ),
            ),
          ),
        Positioned(
          top: 10,
          left: 10,
          right: 36,
          child: Row(
            children: [
              AppUserAvatar(
                imageUrl: avatar,
                displayName: name,
                radius: 11,
                onTap: _post == null
                    ? null
                    : () => PostPublisherDisplay.open(context, _post!),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.15,
                    shadows: [
                      Shadow(color: Color(0x88000000), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.showActions)
          Positioned(
            left: widget.mine ? 8 : null,
            right: widget.mine ? null : 8,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _overlayAction(
                  icon: Icons.send_outlined,
                  tooltip: 'Поделиться',
                  onTap: _post == null ? null : _share,
                ),
                const SizedBox(height: 16),
                _overlayAction(
                  icon: _saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  tooltip: _saved ? 'Убрать из сохранённых' : 'Сохранить',
                  onTap: _post == null ? null : _toggleSave,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _photoFooter({required String name, required String? caption}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              TextSpan(
                text: ' $caption',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _overlayAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 22,
            color: Colors.white,
            shadows: const [
              Shadow(color: Color(0xAA000000), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    final post = _post;
    final raw = post == null ? null : SharedPostMedia.posterUrl(post);
    final resolved = raw != null && raw.isNotEmpty
        ? ServerConfig.resolveMediaUrl(raw)
        : null;
    if (resolved == null) {
      return const ColoredBox(
        color: Color(0xFF1A1A1A),
        child: SizedBox.expand(),
      );
    }
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 720,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1A1A1A)),
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1A1A)),
    );
  }
}
