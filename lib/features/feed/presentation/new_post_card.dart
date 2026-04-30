// Новая карточка поста для нового API
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/report_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/favorites_service.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../screens/detail_page.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/post_card_container.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../services/api_service.dart';
import '../../../services/server_config.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';

class NewPostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onCommentTap;
  final VoidCallback? onAuthorTap;
  
  const NewPostCard({
    Key? key,
    required this.post,
    this.onCommentTap,
    this.onAuthorTap,
  }) : super(key: key);
  
  @override
  State<NewPostCard> createState() => _NewPostCardState();
}

class _NewPostCardState extends State<NewPostCard> {
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostsCount = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReposting = false;
  int? _currentUserId;
  
  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    _loadCurrentUserId();
  }
  
  Future<void> _loadCurrentUserId() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (mounted) {
        setState(() => _currentUserId = user?.id);
      }
    } catch (e) {
      // Игнорируем ошибки
    }
  }
  
  bool get _isAuthor => _currentUserId != null && _currentUserId == widget.post.userId;
  
  Future<void> _toggleLike() async {
    if (_isLoading) return;
    
    // Проверяем авторизацию
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
    
    setState(() {
      _isLoading = true;
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    
    try {
      final response = _isLiked
          ? await LikeService.likePost(widget.post.id)
          : await LikeService.unlikePost(widget.post.id);
      
      setState(() {
        _likesCount = response.likesCount;
      });
    } catch (e) {
      // Откатываем изменения при ошибке
      setState(() {
        _isLiked = !_isLiked;
        _likesCount += _isLiked ? 1 : -1;
      });
      
      if (mounted) {
        final errorMessage = e.toString().contains('Not authenticated') || 
                            e.toString().contains('401')
            ? 'Войдите, чтобы поставить лайк'
            : 'Ошибка при установке лайка: ${e.toString().replaceAll('Exception: ', '')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      // Откатываем изменения при ошибке
      setState(() {
        _isSaved = !_isSaved;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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
    
    if (_isReposted) {
      // Если уже репостнуто, просто удаляем
      setState(() {
        _isReposting = true;
        _isReposted = false;
        _repostsCount = (_repostsCount - 1).clamp(0, double.infinity).toInt();
      });
      
      try {
        await RepostService.deleteRepost(widget.post.id);
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
      await RepostService.createRepost(
        postId: widget.post.id,
        comment: comment,
      );
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
  
  Future<void> _showReportDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ReportDialog(),
    );
    
    if (result == null) return;
    
    try {
      await ReportService.reportPost(
        postId: widget.post.id,
        reason: result['reason'] as String,
        comment: result['comment'] as String?,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба отправлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      try {
        return DateFormat('d MMM', 'ru').format(date);
      } catch (e) {
        return DateFormat('d MMM').format(date);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    final author = post.author;  // Автор оригинального поста
    final repostedBy = post.repostedBy;  // Тот, кто репостнул
    final channel = post.channel;
    
    // Логика отображения автора:
    // 1. Если пост репостнут - в шапке показываем того, кто репостнул, ниже - оригинального автора
    // 2. Если пост из канала (channelId != null) - показываем канал
    // 3. Иначе - показываем автора поста
    final isRepost = repostedBy != null;
    final isFromChannel = post.channelId != null || post.communityId != null;
    
    // Определяем оригинального автора поста (канал или пользователь)
    String? originalAuthorName;
    String? originalAuthorAvatar;
    bool originalAuthorIsChannel = false;
    
    if (isFromChannel) {
      // Оригинальный автор - канал
      originalAuthorName = channel?.name ?? 'Канал';
      originalAuthorAvatar = channel?.avatarUrl;
      originalAuthorIsChannel = true;
    } else {
      // Оригинальный автор - пользователь
      originalAuthorName = author?.name ?? post.author?.name;
      originalAuthorAvatar = author?.avatarUrl ?? post.author?.avatarUrl;
      originalAuthorIsChannel = false;
    }
    
    // Имя и аватар для шапки
    String displayName;
    String? displayAvatar;
    
    if (isRepost) {
      // Репост - в шапке показываем того, кто репостнул
      displayName = repostedBy.name;
      displayAvatar = repostedBy.avatarUrl;
    } else if (isFromChannel) {
      // Пост из канала - показываем канал
      displayName = channel?.name ?? 'Канал';
      displayAvatar = channel?.avatarUrl;
    } else {
      // Пост из профиля пользователя - показываем автора
      displayName = author?.name ?? post.author?.name ?? 'Неизвестный';
      displayAvatar = author?.avatarUrl ?? post.author?.avatarUrl;
    }
    
    final displayInitial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    
    // Логирование для отладки постов из каналов
    if (post.communityId != null) {
      print('🔍 [POST CARD] Rendering channel post ${post.id}, communityId=${post.communityId}, channel=${channel?.name}, repostedBy=${repostedBy?.name}');
    }
    
    // Красивая карточка с тенью и скруглениями
    return PostCardContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка поста (Instagram-стиль: компактная)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Аватар (того, кто репостнул, или канала, или автора)
                GestureDetector(
                  onTap: widget.onAuthorTap,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: displayAvatar != null
                        ? CachedNetworkImageProvider(displayAvatar)
                        : null,
                    child: displayAvatar == null
                        ? Text(
                            displayInitial,
                            style: const TextStyle(fontSize: 18),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Имя и время
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: widget.onAuthorTap,
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // Показываем бейдж "Канал" только для постов из каналов (не репостов)
                          if (isFromChannel && !isRepost) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Канал',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Если репост, показываем оригинального автора со стрелочкой
                      if (isRepost && originalAuthorName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Стрелочка вниз
                            Icon(
                              Icons.arrow_downward,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            // Аватар оригинального автора (кликабельный)
                            GestureDetector(
                              onTap: () {
                                // Если оригинальный автор - канал, открываем канал
                                if (originalAuthorIsChannel && post.channelId != null) {
                                  context.push('/channel/${post.channelId}');
                                } else if (!originalAuthorIsChannel && post.userId != null) {
                                  // Если оригинальный автор - пользователь, открываем профиль
                                  context.push('/profile?userId=${post.userId}');
                                }
                              },
                              child: originalAuthorAvatar != null
                                  ? CircleAvatar(
                                      radius: 10,
                                      backgroundImage: CachedNetworkImageProvider(originalAuthorAvatar),
                                    )
                                  : originalAuthorName != null
                                      ? CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.grey[400],
                                          child: Text(
                                            originalAuthorName[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 6),
                            // Имя оригинального автора (кликабельное)
                            GestureDetector(
                              onTap: () {
                                // Если оригинальный автор - канал, открываем канал
                                if (originalAuthorIsChannel && post.channelId != null) {
                                  context.push('/channel/${post.channelId}');
                                } else if (!originalAuthorIsChannel && post.userId != null) {
                                  // Если оригинальный автор - пользователь, открываем профиль
                                  context.push('/profile?userId=${post.userId}');
                                }
                              },
                              child: Text(
                                originalAuthorName,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (originalAuthorIsChannel) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'Канал',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ]
                      // Для постов из каналов показываем описание канала или "Канал"
                      else if (isFromChannel)
                        Text(
                          channel?.description ?? 'Канал',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      // Для постов из профиля показываем username автора
                      else if (author?.username != null)
                        Text(
                          '@${author!.username}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      Text(
                        _formatDate(post.publishedAt ?? post.createdAt),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Меню (3 точки) - справа в шапке
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (value) async {
                    if (value == 'analytics') {
                      context.push('/analytics?postId=${widget.post.id}');
                    } else if (value == 'report') {
                      _showReportDialog();
                    } else if (value == 'edit') {
                      if (widget.post.channelId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Редактирование постов профиля будет доступно в следующем обновлении')),
                        );
                      } else {
                        context.push(
                          '/channel/${widget.post.channelId}/post/${widget.post.id}/edit',
                          extra: widget.post,
                        );
                      }
                    } else if (value == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Удалить пост?'),
                          content: const Text('Вы уверены, что хотите удалить этот пост? Это действие нельзя отменить.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Удаление постов профиля будет доступно в следующем обновлении')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    if (_isAuthor && widget.post.channelId == null) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Редактировать'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Удалить', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'analytics',
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Аналитика'),
                          ],
                        ),
                      ),
                    ] else if (_isAuthor) ...[
                      const PopupMenuItem(
                        value: 'analytics',
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Аналитика'),
                          ],
                        ),
                      ),
                    ],
                    if (!_isAuthor)
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Пожаловаться'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Медиа (изображения/видео) - сначала фото как в Instagram
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
          if (post.description != null && post.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                post.description!,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          // Действия (Instagram-стиль: кнопки снизу)
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
                                    content: Text('Войдите, чтобы оставить комментарий'),
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
                        if (post.commentsCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(post.commentsCount),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Репост с счетчиком
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.send_outlined, size: 28),
                          onPressed: _isReposting ? null : _toggleRepost,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (_repostsCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(_repostsCount),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // Сохранить
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
  
  // Используем утилиту для форматирования чисел
  String _formatCount(int count) => NumberFormatter.formatCount(count);
  
  /// Получить прокси URL для изображений Spoonacular (для обхода CORS на веб)
  String _getProxyUrl(String originalUrl) {
    // Для Flutter Web используем прокси через бэкенд для обхода CORS
    // Для других платформ используем оригинальный URL
    if (originalUrl.startsWith('https://img.spoonacular.com') || 
        originalUrl.startsWith('https://spoonacular.com')) {
      // Используем прокси только для Spoonacular изображений
      final baseUrl = '${ApiService.baseUrl}/api/v1';
      final encodedUrl = Uri.encodeComponent(originalUrl);
      final proxyUrl = '$baseUrl/recipes/image-proxy?url=$encodedUrl';
      debugPrint('🖼️ Using proxy URL for Spoonacular image: $proxyUrl');
      return proxyUrl;
    }
    // Для других URL возвращаем оригинал
    return originalUrl;
  }
  
  /// Построить виджет для отображения медиа поста
  Widget _buildMedia(PostModel post) {
    // Получаем медиа из body
    final body = post.body;
    if (body == null) return const SizedBox.shrink();
    
    final media = body['media'] as List<dynamic>?;
    
    // Если media пустой, но есть image в body (для рецептов Spoonacular), создаем media
    List<dynamic>? effectiveMedia = media;
    if ((media == null || media.isEmpty) && (body['image'] != null || body['source_image'] != null)) {
      final imageUrl = body['image'] as String? ?? body['source_image'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        effectiveMedia = [
          {
            'type': 'image',
            'url': imageUrl,
          }
        ];
      }
    }
    
    if (effectiveMedia == null || effectiveMedia.isEmpty) return const SizedBox.shrink();
    
    // Показываем изображения для всех типов постов, если они есть (как в Telegram)
    final images = effectiveMedia.where((m) => m['type'] == 'image').toList();
    if (images.isNotEmpty) {
      // Обработчик клика для открытия детальной страницы поста
      void onMediaTap() {
        if (post.channelId != null) {
          // Если пост из канала, открываем детальную страницу поста канала
          context.push('/channel/${post.channelId}/post/${post.id}');
        }
        // Для обычных постов пока просто ничего не делаем (можно добавить роут позже)
      }
      
      // Обработчик клика для рецепта - открываем рецепт
      void onRecipeTap() {
        final body = post.body;
        if (body == null) {
          debugPrint('❌ onRecipeTap: body is null');
          return;
        }
        
        try {
          debugPrint('🔍 onRecipeTap вызван для post.id=${post.id}, post.type=${post.type}');
          debugPrint('🔍 body keys: ${body.keys.toList()}');
          debugPrint('🔍 post.id type: ${post.id.runtimeType}');
          
          // Получаем изображение из media или body
          String? imageUrl;
          
          // Сначала пробуем из body (для рецептов Spoonacular)
          imageUrl = body['image'] as String? ?? body['source_image'] as String?;
          
          // Если не найдено, пробуем из media
          if (imageUrl == null || imageUrl.isEmpty) {
            final media = body['media'] as List<dynamic>?;
            if (media != null && media.isNotEmpty) {
              try {
                final firstImage = media.firstWhere(
                  (m) => m['type'] == 'image',
                ) as Map<String, dynamic>?;
                imageUrl = firstImage?['url'] as String?;
              } catch (e) {
                debugPrint('⚠️ Изображение не найдено в media');
              }
            }
          }
          
          debugPrint('🔍 imageUrl: $imageUrl');
          
          // Извлекаем ID рецепта
          // Для рецептов Spoonacular ID уже извлечен в PostModel.fromJson из строки "spoonacular_123"
          int recipeId = post.id;
          
          // Если это рецепт Spoonacular, проверяем body для подтверждения
          if (body['spoonacular_recipe_id'] != null) {
            final spoonacularId = body['spoonacular_recipe_id'];
            final extractedId = spoonacularId is int ? spoonacularId : int.tryParse(spoonacularId.toString());
            if (extractedId != null && extractedId != 0) {
              recipeId = extractedId;
              debugPrint('🔍 Найден spoonacular_recipe_id в body: $recipeId');
            }
          }
          
          // Если ID все еще 0, это проблема
          if (recipeId == 0) {
            debugPrint('❌ Ошибка: recipeId = 0');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ошибка: не удалось определить ID рецепта'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
          
          debugPrint('✅ Используем recipeId: $recipeId');
          
          // Используем переведенные данные, если они есть
          final title = body['translated_title'] as String? ?? post.title ?? 'Рецепт';
          final ingredients = (body['translated_ingredients'] as List<dynamic>?) ?? 
                              (body['ingredients'] as List<dynamic>?) ?? [];
          final steps = (body['translated_steps'] as List<dynamic>?) ?? 
                        (body['steps'] as List<dynamic>?) ?? [];
          
          debugPrint('🔍 title: $title, ingredients: ${ingredients.length}, steps: ${steps.length}');
          
          // Собираем данные рецепта из body
          final recipeData = <String, dynamic>{
            'id': recipeId,
            'title': title,
            'image': imageUrl,
            'source_image': body['source_image'] as String? ?? imageUrl,
            'ingredients': ingredients,
            'steps': steps,
            'translated_title': body['translated_title'],
            'translated_ingredients': body['translated_ingredients'],
            'translated_steps': body['translated_steps'],
            'usedIngredientCount': ingredients.length,
            'calories': body['calories'],
            'nutrition': body['nutrition'],
            'source': 'spoonacular',
          };
          
          debugPrint('🔍 Создаем Recipe с id=$recipeId');
          final recipe = Recipe.fromJson(recipeData);
          
          // Получаем информацию о том, является ли рецепт избранным
          final isFavorite = FavoritesService.instance.isFavorite(recipe.id.toString());
          
          debugPrint('✅ Открываем DetailPage для рецепта ${recipe.id}');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DetailPage(
                recipe: recipe,
                isFavorite: isFavorite,
                onToggle: () async {
                  await FavoritesService.instance.toggleFavorite(recipe.id.toString());
                },
              ),
            ),
          );
        } catch (e, stackTrace) {
          debugPrint('❌ Error parsing recipe from post: $e');
          debugPrint('❌ Body: $body');
          debugPrint('❌ Stack trace: $stackTrace');
          
          // Показываем ошибку пользователю
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка при открытии рецепта: $e'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
      
      // Извлекаем URL изображений и применяем прокси для Spoonacular
      final imageUrls = images
          .map((img) => img['url'] as String?)
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .map((url) => _getProxyUrl(url))
          .toList();
      
      if (imageUrls.isNotEmpty) {
        // Instagram-стиль: квадратные изображения
        final isRecipe = post.type == 'recipe';
        final screenWidth = MediaQuery.of(context).size.width;
        return AspectRatio(
          aspectRatio: 1, // Квадратное соотношение как в Instagram
          child: TelegramPhotoGrid(
            imageUrls: imageUrls,
            maxHeight: screenWidth, // Квадратная высота = ширина экрана
            onTap: isRecipe ? onRecipeTap : null, // Для рецептов используем onTap, для обычных постов - полноэкранный просмотр
            enableFullscreen: !isRecipe, // Для рецептов отключаем полноэкранный просмотр, для обычных постов - включаем
          ),
        );
      }
    }
    
    // Показываем видео для всех типов постов, если они есть (Instagram-style inline autoplay)
    final videos = effectiveMedia?.where((m) => m['type'] == 'video').toList() ?? [];
    if (videos.isNotEmpty) {
      final rawVideoUrl = videos[0]['url'] as String;
      final rawThumbnailUrl = videos[0]['thumbnail_url'] as String? ?? body['thumbnail_url'] as String?;
      final videoUrl = ServerConfig.resolveMediaUrl(rawVideoUrl);
      final thumbnailUrl = rawThumbnailUrl != null ? ServerConfig.resolveMediaUrl(rawThumbnailUrl) : null;
      return InlineVideoPlayer(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        aspectRatio: 16 / 9,
        onTap: () {
          context.push(ReelsFullscreenRoute.path, extra: post);
        },
      );
    }
    
    return const SizedBox.shrink();
  }
}

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

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();
  
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _selectedReason = 'spam';
  final _commentController = TextEditingController();
  
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Пожаловаться на пост'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Причина жалобы:'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedReason,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'spam', child: Text('Спам')),
              DropdownMenuItem(value: 'inappropriate', child: Text('Неподходящий контент')),
              DropdownMenuItem(value: 'copyright', child: Text('Нарушение авторских прав')),
              DropdownMenuItem(value: 'other', child: Text('Другое')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedReason = value);
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: 'Комментарий (опционально)',
              hintText: 'Опишите проблему...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
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
              'reason': _selectedReason,
              'comment': _commentController.text.trim().isEmpty
                  ? null
                  : _commentController.text.trim(),
            });
          },
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}


