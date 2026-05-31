import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../models/post.dart';
import '../../../services/auth_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/share_link_service.dart';
import '../../../widgets/report_content_dialog.dart';

Future<void> _feedSyncBookmark(
  BuildContext context,
  Post post, {
  Future<void> Function(String postId)? onBookmarkChanged,
}) async {
  final wasSaved = post.isSaved;
  try {
    if (wasSaved) {
      await SavedPostsService.unsavePost(post.id);
    } else {
      await SavedPostsService.savePost(post.id);
    }
    await onBookmarkChanged?.call(post.idString);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasSaved ? 'Удалено из сохранённых' : 'Пост сохранён',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось обновить сохранённые'))),
    );
  }
}

Future<void> _feedCopyPostLink(BuildContext context, Post post) async {
  final link = post.type == 'reel'
      ? ShareLinkService.reelLink(post.id)
      : ShareLinkService.postLink(post.id);
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Ссылка скопирована')),
  );
}

/// Карточка поста в ленте
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onHide,
    required this.onReport,
    this.onBlockAuthor,
    this.onBookmarkChanged,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onHide;
  final VoidCallback onReport;
  /// Локально скрыть автора в ленте; для вложенного репоста обычно `null`.
  final VoidCallback? onBlockAuthor;
  /// После save/unsync — обновить пост в ленте (например [FeedController.refreshPost]).
  final Future<void> Function(String postId)? onBookmarkChanged;

  @override
  Widget build(BuildContext context) {
    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('d MMM в HH:mm', 'ru');
    } catch (e) {
      dateFormat = DateFormat('d MMM at HH:mm');
    }

    // Instagram-стиль: компактная карточка без Card, белый фон
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка поста (Instagram-стиль)
          _PostHeader(
            post: post,
            dateFormat: dateFormat,
            onMenuTap: () => _showMenu(context),
          ),
          
          // Медиа контент (сначала фотографии) - квадратные как в Instagram
          if (post.photos != null && post.photos!.isNotEmpty)
            _PostPhotos(photos: post.photos!),

          // Контент поста (текст после фотографий) - компактный padding
          if (post.text != null && post.text!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                post.text!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          if (post.videoUrl != null)
            _PostVideo(videoUrl: post.videoUrl!, thumbnail: post.videoThumbnail),

          if (post.linkUrl != null)
            _PostLink(
              url: post.linkUrl!,
              preview: post.linkPreview,
            ),

          if (post.poll != null)
            _PostPoll(poll: post.poll!),

          // Репост
          if (post.repostedPost != null)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: PostCard(
                post: post.repostedPost!,
                onLike: () {},
                onComment: () {},
                onShare: () {},
                onHide: () {},
                onReport: () => reportPostWithDialog(
                  context,
                  post.repostedPost!.id,
                ),
                onBlockAuthor: null,
                onBookmarkChanged: null,
              ),
            ),

          // Теги
          if (post.tags != null && post.tags!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: post.tags!.map((tag) {
                  return Chip(
                    label: Text('#$tag'),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),

          // Метика рекламы
          if (post.isAd)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  Icon(Icons.ads_click, size: 16, color: Colors.amber.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Реклама',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Действия (Instagram-стиль: кнопки снизу)
          _PostActions(
            post: post,
            onLike: onLike,
            onComment: onComment,
            onShare: onShare,
            onBookmarkChanged: onBookmarkChanged,
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext cardContext) {
    final me = AuthService.instance.currentUser?.id;
    final canBlockAuthor =
        onBlockAuthor != null && me != null && post.userId != me;

    showModalBottomSheet<void>(
      context: cardContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                post.isSaved ? Icons.bookmark_remove : Icons.bookmark_border,
              ),
              title: Text(post.isSaved ? 'Убрать из сохранённых' : 'Сохранить'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _feedSyncBookmark(
                  cardContext,
                  post,
                  onBookmarkChanged: onBookmarkChanged,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Скрыть'),
              onTap: () {
                Navigator.pop(sheetContext);
                onHide();
              },
            ),
            if (canBlockAuthor)
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Не показывать от автора'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onBlockAuthor!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Пожаловаться'),
              onTap: () {
                Navigator.pop(sheetContext);
                onReport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Скопировать ссылку'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _feedCopyPostLink(cardContext, post);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Шапка поста (Instagram-стиль: компактная)
class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.dateFormat,
    required this.onMenuTap,
  });

  final Post post;
  final DateFormat? dateFormat;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    // Используем имя пользователя из author, если доступно, иначе из userId
    final authorName = post.groupName ?? 
                       post.authorName ?? 
                       (post.author?.name) ??
                       'Неизвестный';
    final authorAvatar = post.groupAvatar ?? 
                        post.authorAvatar ?? 
                        (post.author?.avatarUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: authorAvatar != null ? NetworkImage(authorAvatar) : null,
            child: authorAvatar == null
                ? Text(authorName.substring(0, 1).toUpperCase())
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  dateFormat?.format(post.createdAt) ?? post.createdAt.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 24),
            onPressed: onMenuTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Фото в посте (Instagram-стиль: квадратные изображения)
class _PostPhotos extends StatelessWidget {
  const _PostPhotos({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      // Одно фото - квадратное как в Instagram
      return AspectRatio(
        aspectRatio: 1,
        child: Image.network(
          photos.first,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    // Несколько фото - сетка как в Instagram
    if (photos.length == 2) {
      // Два фото рядом в квадратной области
      return AspectRatio(
        aspectRatio: 1,
        child: Row(
          children: [
            Expanded(
              child: Image.network(
                photos[0],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Image.network(
                photos[1],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ],
        ),
      );
    }

    if (photos.length == 3) {
      // Три фото: одно большое слева, два маленьких справа в квадратной области
      return AspectRatio(
        aspectRatio: 1,
        child: Row(
          children: [
            Expanded(
              child: Image.network(
                photos[0],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Image.network(
                      photos[1],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Image.network(
                      photos[2],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4+ фото - квадратная сетка 2x2 с индикатором количества
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
      itemCount: photos.length > 4 ? 4 : photos.length,
      itemBuilder: (context, index) {
        if (index == 3 && photos.length > 4) {
          // Показать индикатор "еще фото"
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                photos[index],
                fit: BoxFit.cover,
              ),
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Text(
                    '+${photos.length - 4}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Image.network(
          photos[index],
          fit: BoxFit.cover,
        );
      },
      ),
    );
  }
}

/// Видео в посте
class _PostVideo extends StatefulWidget {
  const _PostVideo({required this.videoUrl, this.thumbnail});

  final String videoUrl;
  final String? thumbnail;

  @override
  State<_PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<_PostVideo> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SimpleVideoPlayerPage(
              videoUrl: widget.videoUrl,
              title: 'Видео',
            ),
          ),
        );
      },
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (widget.thumbnail != null)
              Image.network(
                widget.thumbnail!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(Icons.videocam, color: Colors.white, size: 48),
                    ),
                  );
                },
              )
            else
              Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.white, size: 48),
                ),
              ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
            ),
          ],
        ),
      ),
    );
  }
}

/// Простая страница видеоплеера для постов
class _SimpleVideoPlayerPage extends StatefulWidget {
  const _SimpleVideoPlayerPage({required this.videoUrl, required this.title});

  final String videoUrl;
  final String title;

  @override
  State<_SimpleVideoPlayerPage> createState() => _SimpleVideoPlayerPageState();
}

class _SimpleVideoPlayerPageState extends State<_SimpleVideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isPaused = false;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _controller.play();
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _initialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: _hasError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Ошибка загрузки видео'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Назад'),
                  ),
                ],
              )
            : !_initialized
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isPaused = !_isPaused;
                        });
                        if (_isPaused) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_controller),
                          // Индикатор паузы
                          if (_isPaused)
                            IgnorePointer(
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.3),
                                child: const Center(
                                  child: Icon(
                                    Icons.pause_circle_filled,
                                    color: Colors.white,
                                    size: 80,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
      ),
      floatingActionButton: _initialized && !_hasError
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Icon(
                _controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}

/// Ссылка в посте
class _PostLink extends StatelessWidget {
  const _PostLink({required this.url, this.preview});

  final String url;
  final String? preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (preview != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: Image.network(
                preview!,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    url,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    url,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Опрос в посте
class _PostPoll extends StatelessWidget {
  const _PostPoll({required this.poll});

  final PollData poll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalVotes = poll.options.fold<int>(0, (sum, o) => sum + o.votes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.poll_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Опрос',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (totalVotes > 0)
                    Text(
                      '$totalVotes ${_votesLabel(totalVotes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                poll.question,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              ...poll.options.map((option) {
                final fraction = (option.percentage / 100).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              option.text,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${option.percentage.toStringAsFixed(0)}%',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (option.votes > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${option.votes} ${_votesLabel(option.votes)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

String _votesLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'голосов';
  if (mod10 == 1) return 'голос';
  if (mod10 >= 2 && mod10 <= 4) return 'голоса';
  return 'голосов';
}

/// Действия с постом (лайк, комментарий, репост)
class _PostActions extends StatefulWidget {
  const _PostActions({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    this.onBookmarkChanged,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final Future<void> Function(String postId)? onBookmarkChanged;

  @override
  State<_PostActions> createState() => _PostActionsState();
}

class _PostActionsState extends State<_PostActions> {
  @override
  Widget build(BuildContext context) {
    final reactions = widget.post.reactions;
    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('d MMM в HH:mm', 'ru');
    } catch (e) {
      dateFormat = DateFormat('d MMM at HH:mm');
    }

    // Instagram-стиль: кнопки действий снизу
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  widget.post.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: widget.post.isLiked ? Colors.red : Colors.black,
                  size: 28,
                ),
                onPressed: widget.onLike,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.comment_outlined, size: 28),
                onPressed: widget.onComment,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.send_outlined, size: 28),
                onPressed: widget.onShare,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  widget.post.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  size: 28,
                ),
                onPressed: () => _feedSyncBookmark(
                  context,
                  widget.post,
                  onBookmarkChanged: widget.onBookmarkChanged,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Счетчики лайков
          Text(
            '${_formatCount(reactions.likes)} отметок "Нравится"',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (widget.post.text == null || widget.post.text!.isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dateFormat.format(widget.post.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}

