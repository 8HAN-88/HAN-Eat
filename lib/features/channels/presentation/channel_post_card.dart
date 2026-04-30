// Карточка поста для канала (без шапки с автором, как в Telegram)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/favorites_service.dart';
import '../../../services/server_config.dart';
import '../../../screens/detail_page.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/post_card_container.dart';
import 'channel_posts_screen.dart';
import '../../../app/app_router.dart';

class ChannelPostCard extends StatefulWidget {
  final PostModel post;
  final int channelId;
  final ChannelDetail channel; // Для проверки прав администратора
  final VoidCallback? onCommentTap;

  const ChannelPostCard({
    Key? key,
    required this.post,
    required this.channelId,
    required this.channel,
    this.onCommentTap,
  }) : super(key: key);

  @override
  State<ChannelPostCard> createState() => _ChannelPostCardState();
}

class _ChannelPostCardState extends State<ChannelPostCard> {
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostsCount = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReposting = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    // Отмечаем пост как прочитанный при загрузке
    _markAsViewed();
    // Проверяем актуальный статус репоста при загрузке
    _checkRepostStatus();
  }

  Future<void> _checkRepostStatus() async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null) return;

      final isReposted = await RepostService.isPostReposted(widget.post.id);
      if (mounted) {
        setState(() {
          _isReposted = isReposted;
        });
      }
    } catch (e) {
      // Игнорируем ошибки проверки статуса
      debugPrint('Ошибка проверки статуса репоста: $e');
    }
  }

  Future<void> _markAsViewed() async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null) return;

      // Вызываем API для отметки поста как прочитанного
      final uri =
          Uri.parse('${ServerConfig.apiBaseUrl}/posts/${widget.post.id}/view');
      await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      // Игнорируем ошибки при отметке просмотра
      debugPrint('Ошибка отметки поста как прочитанного: $e');
    }
  }

  bool get _isAdmin => widget.channel.isAdmin || widget.channel.isOwner;

  Future<void> _toggleLike() async {
    if (_isLoading) return;

    final token = await AuthService.getAccessToken();
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Войдите, чтобы поставить лайк'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Сохраняем исходное состояние для отката
    final originalIsLiked = _isLiked;
    final originalLikesCount = _likesCount;

    setState(() {
      _isLoading = true;
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });

    try {
      final response = _isLiked
          ? await LikeService.likePost(widget.post.id)
          : await LikeService.unlikePost(widget.post.id);

      if (mounted) {
        setState(() {
          _isLoading = false;
          // Используем актуальное состояние с сервера
          _likesCount = response.likesCount;
          _isLiked = response.liked;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Откатываем изменения при ошибке
          _isLiked = originalIsLiked;
          _likesCount = originalLikesCount;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Ошибка: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _toggleRepost() async {
    if (_isReposting) return;

    // Проверяем авторизацию
    final token = await AuthService.getAccessToken();
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Войдите, чтобы сделать репост'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Если уже репостнуто, удаляем репост
    if (_isReposted) {
      setState(() {
        _isReposting = true;
        _isReposted = false;
        _repostsCount = (_repostsCount - 1).clamp(0, double.infinity).toInt();
      });

      try {
        await RepostService.deleteRepost(widget.post.id);

        // После успешного удаления проверяем актуальный статус
        try {
          final isReposted = await RepostService.isPostReposted(widget.post.id);
          if (mounted) {
            setState(() {
              _isReposted = isReposted;
            });
          }
        } catch (e) {
          // Игнорируем ошибку проверки статуса
          debugPrint('Ошибка проверки статуса репоста: $e');
        }
      } catch (e) {
        // Откатываем изменения при ошибке
        setState(() {
          _isReposted = true;
          _repostsCount += 1;
        });

        if (mounted) {
          final errorMessage = e.toString().contains('Not authenticated') ||
                  e.toString().contains('401')
              ? 'Войдите, чтобы убрать репост'
              : 'Ошибка при удалении репоста: ${e.toString().replaceAll('Exception: ', '')}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isReposting = false);
        }
      }
      return;
    }

    // Показываем диалог для репоста с комментарием
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RepostDialog(),
    );

    if (result == null) return; // Пользователь отменил

    final comment = result['comment'] as String?;

    setState(() {
      _isReposting = true;
      _isReposted = true;
      _repostsCount += 1;
    });

    try {
      final response = await RepostService.createRepost(
        postId: widget.post.id,
        comment: comment,
      );

      // После успешного репоста проверяем актуальный статус
      try {
        final isReposted = await RepostService.isPostReposted(widget.post.id);
        if (mounted) {
          setState(() {
            _isReposted = isReposted;
            // Обновляем счетчик из ответа, если доступен
            if (response.reposted) {
              // Счетчик уже увеличен выше, но можно обновить из ответа
            }
          });
        }
      } catch (e) {
        // Игнорируем ошибку проверки статуса
        debugPrint('Ошибка проверки статуса репоста: $e');
      }
    } catch (e) {
      // Откатываем изменения при ошибке
      setState(() {
        _isReposted = false;
        _repostsCount = (_repostsCount - 1).clamp(0, double.infinity).toInt();
      });

      if (mounted) {
        final errorMessage = e.toString().contains('Not authenticated') ||
                e.toString().contains('401')
            ? 'Войдите, чтобы сделать репост'
            : e.toString().contains('already reposted')
                ? 'Вы уже репостнули этот пост'
                : e.toString().contains('Cannot repost your own')
                    ? 'Нельзя репостнуть свой пост'
                    : 'Ошибка при репосте: ${e.toString().replaceAll('Exception: ', '')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReposting = false);
      }
    }
  }

  Future<void> _copyPostLink() async {
    // Формируем ссылку на пост
    final baseUrl = ServerConfig.baseUrl;
    final postUrl = widget.post.channelId != null
        ? '$baseUrl/channel/${widget.post.channelId}/post/${widget.post.id}'
        : '$baseUrl/post/${widget.post.id}';

    await Clipboard.setData(ClipboardData(text: postUrl));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ссылка скопирована в буфер обмена'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleSave() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _isSaved = !_isSaved;
    });

    try {
      if (_isSaved) {
        await SavedPostsService.savePost(widget.post.id);
      } else {
        await SavedPostsService.unsavePost(widget.post.id);
      }
    } catch (e) {
      setState(() {
        _isSaved = !_isSaved;
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    // Показываем точное время: часы и минуты
    try {
      return DateFormat('HH:mm', 'ru').format(date);
    } catch (e) {
      return DateFormat('HH:mm').format(date);
    }
  }

  // Используем утилиту для форматирования чисел
  String _formatCount(int count) => NumberFormatter.formatCount(count);

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    // Используем ChannelPostCardContainer для кастомизации фона канала
    // В будущем можно добавить поля backgroundColor и accentColor в ChannelDetail
    return ChannelPostCardContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Медиа (изображения/видео) - БЕЗ шапки с автором
          _buildMedia(post),

          // Контент (текст после фото)
          if (post.title != null && post.title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                post.title!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Описание и время публикации (в одной строке)
          if (post.description != null && post.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      post.description!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Количество просмотров
                      if (post.viewsCount > 0) ...[
                        Icon(Icons.visibility_outlined,
                            size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _formatCount(post.viewsCount),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Время публикации
                      Text(
                        _formatDate(post.publishedAt ?? post.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Количество просмотров
                    if (post.viewsCount > 0) ...[
                      Icon(Icons.visibility_outlined,
                          size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(post.viewsCount),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Время публикации
                    Text(
                      _formatDate(post.publishedAt ?? post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Действия (лайк, комментарий, репост, избранное + меню для админов)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Лайк с счетчиком
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.black,
                            size: 28,
                          ),
                          onPressed: _isLoading ? null : _toggleLike,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (_likesCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(_likesCount),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Комментарий с счетчиком
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.comment_outlined, size: 28),
                          onPressed: () async {
                            final token = await AuthService.getAccessToken();
                            if (token == null && widget.onCommentTap != null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Войдите, чтобы оставить комментарий'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }
                            widget.onCommentTap?.call();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Всегда показываем счетчик комментариев (даже если 0)
                        const SizedBox(width: 4),
                        Text(
                          _formatCount(post.commentsCount),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Репост с счетчиком
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.send_outlined,
                            size: 28,
                            color: _isReposted ? Colors.green : Colors.black,
                          ),
                          onPressed: _isReposting ? null : _toggleRepost,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Всегда показываем счетчик репостов (даже если 0)
                        const SizedBox(width: 4),
                        Text(
                          _formatCount(_repostsCount),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Меню (справа, перед избранным)
                    IconButton(
                      icon: const Icon(Icons.more_horiz, size: 28),
                      onPressed: () => _showPostMenu(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    // Избранное
                    IconButton(
                      icon: Icon(
                        _isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: _isSaved ? Colors.amber : Colors.black,
                        size: 28,
                      ),
                      onPressed: _isSaving ? null : _toggleSave,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPostMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Копировать ссылку
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Копировать ссылку'),
              onTap: () {
                Navigator.pop(context);
                _copyPostLink();
              },
            ),
            // Меню для админов
            if (_isAdmin) ...[
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Аналитика'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/analytics?postId=${widget.post.id}');
                },
              ),
              if (widget.post.channelId != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push(
                      '/channel/${widget.post.channelId}/post/${widget.post.id}/edit',
                      extra: widget.post,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMedia(PostModel post) {
    final body = post.body;
    if (body == null) return const SizedBox.shrink();

    final media = body['media'] as List<dynamic>?;
    if (media == null || media.isEmpty) return const SizedBox.shrink();

    final images = media.where((m) => m['type'] == 'image').toList();
    if (images.isNotEmpty) {
      void onMediaTap() {
        if (post.channelId != null) {
          context.push('/channel/${post.channelId}/post/${post.id}');
        }
      }

      // Обработчик клика для рецепта - открываем рецепт
      void onRecipeTap() {
        final body = post.body;
        if (body == null) return;

        try {
          // Получаем изображение из media
          final media = body['media'] as List<dynamic>?;
          String? imageUrl;
          if (media != null && media.isNotEmpty) {
            try {
              final firstImage = media.firstWhere(
                (m) => m['type'] == 'image',
              ) as Map<String, dynamic>?;
              imageUrl = firstImage?['url'] as String?;
              if (imageUrl != null && imageUrl.isNotEmpty) {
                imageUrl = ServerConfig.resolveMediaUrl(imageUrl!);
              }
            } catch (e) {
              // Изображение не найдено
            }
          }

          // Собираем данные рецепта из body
          final recipeData = <String, dynamic>{
            'id': post.id, // Используем ID поста как ID рецепта
            'title': post.title ?? 'Рецепт',
            'image': imageUrl,
            'ingredients': body['ingredients'] ?? [],
            'steps': body['steps'] ?? [],
            'usedIngredientCount': (body['ingredients'] as List?)?.length ?? 0,
            'calories': body['calories'],
          };

          final recipe = Recipe.fromJson(recipeData);
          // Получаем информацию о том, является ли рецепт избранным
          final isFavorite =
              FavoritesService.instance.isFavorite(recipe.id.toString());
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DetailPage(
                recipe: recipe,
                isFavorite: isFavorite,
                onToggle: () async {
                  await FavoritesService.instance
                      .toggleFavorite(recipe.id.toString());
                },
              ),
            ),
          );
        } catch (e, stackTrace) {
          debugPrint('Error parsing recipe from post: $e');
          debugPrint('Body: $body');
          debugPrint('Stack trace: $stackTrace');
        }
      }

      final imageUrls = images
          .map((img) => img['url'] as String?)
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .map(ServerConfig.resolveMediaUrl)
          .toList();

      if (imageUrls.isNotEmpty) {
        final isRecipe = post.type == 'recipe';
        final screenWidth = MediaQuery.of(context).size.width;

        // Для одной картинки тоже используем TelegramPhotoGrid для единообразия
        return AspectRatio(
          aspectRatio: 1,
          child: TelegramPhotoGrid(
            imageUrls: imageUrls,
            maxHeight: screenWidth,
            onTap: isRecipe
                ? onRecipeTap
                : null, // Для рецептов используем onTap, для обычных постов - полноэкранный просмотр
            enableFullscreen:
                !isRecipe, // Для рецептов отключаем полноэкранный просмотр, для обычных постов - включаем
          ),
        );
      }
    }

    final videos = media.where((m) => m['type'] == 'video').toList();
    if (videos.isNotEmpty) {
      final videoUrl = ServerConfig.resolveMediaUrl(videos[0]['url'] as String);
      final thumbnailUrl = body['thumbnail_url'] != null
          ? ServerConfig.resolveMediaUrl(body['thumbnail_url'] as String)
          : null;
      return InlineVideoPlayer(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        aspectRatio: 1.0,
        onTap: () => context.push(ReelsFullscreenRoute.path, extra: post),
      );
    }

    return const SizedBox.shrink();
  }
}

// Диалог для репоста
class _RepostDialog extends StatefulWidget {
  const _RepostDialog();

  @override
  State<_RepostDialog> createState() => _RepostDialogState();
}

class _RepostDialogState extends State<_RepostDialog> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Репостнуть пост?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: 'Комментарий (опционально)',
              hintText: 'Добавьте комментарий к репосту...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'comment': _commentController.text.trim().isEmpty
                  ? null
                  : _commentController.text.trim(),
            });
          },
          child: const Text('Репостнуть'),
        ),
      ],
    );
  }
}
