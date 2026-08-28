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
}

/// Instagram-style reel card in chat: 9:16 poster, play, author, share/save.
class ChatReelPreview extends StatefulWidget {
  const ChatReelPreview({
    super.key,
    required this.postId,
    required this.url,
    this.mine = true,
    this.compact = false,
    this.showActions = true,
  });

  final int postId;
  final String url;
  final bool mine;
  final bool compact;
  final bool showActions;

  @override
  State<ChatReelPreview> createState() => _ChatReelPreviewState();
}

class _ChatReelPreviewState extends State<ChatReelPreview> {
  PostModel? _post;
  bool _loading = true;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChatReelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _post = _ReelPostCache.posts[widget.postId];
    });
    final post = await _ReelPostCache.fetch(widget.postId);
    var saved = post?.isSaved ?? false;
    if (post != null) {
      try {
        saved = await SavedPostsService.isPostSaved(post.id);
      } catch (_) {}
    }
    if (!mounted || widget.postId != (post?.id ?? widget.postId)) return;
    setState(() {
      _post = post;
      _saved = saved;
      _loading = false;
    });
  }

  Future<void> _open() async {
    await openAppOrExternalLink(context, widget.url);
  }

  Future<void> _share() async {
    final post = _post;
    if (post == null) return;
    await ShareActionSheet.showForReel(context, reel: post);
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
      showErrorSnackBar(context, e, fallback: 'Не удалось сохранить');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _compactCard(context);
    }
    final card = _tallCard(context);
    if (!widget.showActions) return card;
    final actions = _sideActions(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.mine) ...[
            actions,
            const SizedBox(width: 8),
          ],
          card,
          if (!widget.mine) ...[
            const SizedBox(width: 8),
            actions,
          ],
        ],
      ),
    );
  }

  Widget _sideActions(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleAction(
          icon: Icons.send_rounded,
          tooltip: 'Поделиться',
          onTap: _post == null ? null : _share,
        ),
        const SizedBox(height: 10),
        _circleAction(
          icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          tooltip: _saved ? 'Убрать из сохранённых' : 'Сохранить',
          onTap: _post == null ? null : _toggleSave,
        ),
      ],
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _compactCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = _post;
    final name = post == null ? 'Рилс' : PostPublisherDisplay.label(post);
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
                child: _poster(borderRadius: 0),
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
                      'Рилс',
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

  Widget _tallCard(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.52).clamp(168.0, 216.0);
    final height = width * 16 / 9;
    final post = _post;
    final name = post == null ? 'HanWe' : PostPublisherDisplay.label(post);
    final avatar = post == null ? null : PostPublisherDisplay.avatarUrl(post);

    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _poster(borderRadius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0x66000000), Color(0x00000000)],
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
              else
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    AppUserAvatar(
                      imageUrl: avatar,
                      displayName: name,
                      radius: 12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 10,
                bottom: 10,
                child: Icon(
                  Icons.smart_display_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster({required double borderRadius}) {
    final thumb = _post?.videoThumbnail;
    final resolved = thumb != null && thumb.isNotEmpty
        ? ServerConfig.resolveMediaUrl(thumb)
        : null;
    final image = resolved == null
        ? const ColoredBox(
            color: Color(0xFF1A1A1A),
            child: SizedBox.expand(),
          )
        : CachedNetworkImage(
            imageUrl: resolved,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: 640,
            placeholder: (_, __) => const ColoredBox(color: Color(0xFF1A1A1A)),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF1A1A1A)),
          );
    if (borderRadius <= 0) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );
  }
}
