// Карточка поста в канале — тот же каркас, что и в ленте (шапка канала, мета, действия).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../models/post.dart' show PollData;
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/comment_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/favorites_service.dart';
import '../../../services/server_config.dart';
import '../../../screens/detail_page.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/post_card_container.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/post_poll_section.dart';
import '../../../services/channel_service.dart';
import '../../../services/api_service.dart';
import '../../../app/app_router.dart';
import '../../../services/subscription_service.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/recipe_visibility_badge.dart';
import '../../../widgets/recipe_visibility_selector.dart';
import '../../../utils/api_error_parser.dart';
import '../../subscription/presentation/widgets/creator_recipe_upsell.dart';
import 'package:url_launcher/url_launcher.dart';

int? _channelRepostOriginalPostId(Map<String, dynamic>? body) {
  final raw = body?['repost_original_post_id'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

String? _channelRepostUserComment(PostModel post) {
  final body = post.body;
  final fromBody = body?['repost_to_channel_comment'];
  if (fromBody is String && fromBody.trim().isNotEmpty) {
    return fromBody.trim();
  }
  final desc = post.description;
  if (desc == null || desc.trim().isEmpty) return null;
  final blocks = desc.split(RegExp(r'\n\n+', multiLine: true));
  if (blocks.isEmpty) return null;
  final first = blocks.first.trim();
  if (first.isEmpty || first.startsWith('Репост:')) return null;
  return first;
}

bool _isMeaningfulTitle(String? s) {
  if (s == null) return false;
  final t = s.trim();
  return t.isNotEmpty && t != '.' && t != '…' && t != '...';
}

class ChannelPostCard extends StatefulWidget {
  final PostModel post;
  final int channelId;
  final ChannelDetail channel; // Для проверки прав администратора
  final Future<void> Function()? onCommentTap;

  /// Нажатие по карточке (например открыть пост); при задании — лёгкая анимация нажатия.
  final VoidCallback? onCardTap;

  /// После успешного удаления поста (обновить список).
  final VoidCallback? onPostDeleted;

  const ChannelPostCard({
    super.key,
    required this.post,
    required this.channelId,
    required this.channel,
    this.onCommentTap,
    this.onCardTap,
    this.onPostDeleted,
  });

  @override
  State<ChannelPostCard> createState() => _ChannelPostCardState();
}

class _ChannelPostCardState extends State<ChannelPostCard>
    with SingleTickerProviderStateMixin {
  late PostModel _displayPost;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostsCount = 0;
  int _displayCommentsCount = 0;
  bool _promotedLocally = false;
  String? _visibilityOverride;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReposting = false;
  AnimationController? _pressController;
  Animation<double>? _scaleAnimation;

  int? _channelRepostOriginalIdCache;
  Future<PostModel?>? _channelRepostOriginalFuture;

  void _syncChannelRepostFuture() {
    final id = _channelRepostOriginalPostId(widget.post.body);
    if (id == null) {
      _channelRepostOriginalIdCache = null;
      _channelRepostOriginalFuture = null;
      return;
    }
    if (_channelRepostOriginalIdCache != id) {
      _channelRepostOriginalIdCache = id;
      _channelRepostOriginalFuture = ApiService.getPostById(id);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _displayPost = widget.post;
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    _displayCommentsCount = widget.post.commentsCount;
    if (widget.onCardTap != null) {
      _pressController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
      );
      _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(
          parent: _pressController!,
          curve: Curves.easeInOut,
        ),
      );
    }
    _markAsViewed();
    _checkRepostStatus();
    _syncChannelRepostFuture();
  }

  @override
  void didUpdateWidget(covariant ChannelPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _channelRepostOriginalIdCache = null;
      _channelRepostOriginalFuture = null;
      _displayPost = widget.post;
    } else if (oldWidget.post != widget.post) {
      _displayPost = widget.post;
    }
    if (oldWidget.post.id == widget.post.id && oldWidget.post != widget.post) {
      _isLiked = widget.post.isLiked;
      _likesCount = widget.post.likesCount;
      _isSaved = widget.post.isSaved ?? false;
      _isReposted = widget.post.isReposted ?? false;
      _repostsCount = widget.post.repostsCount;
      _displayCommentsCount = widget.post.commentsCount;
      _visibilityOverride = null;
    }
    _syncChannelRepostFuture();
  }

  Future<void> _reloadDisplayPost() async {
    try {
      final fresh = await ApiService.getPostById(widget.post.id);
      if (fresh != null && mounted) {
        setState(() {
          _displayPost = fresh;
          _displayCommentsCount = fresh.commentsCount;
          _isLiked = fresh.isLiked;
          _likesCount = fresh.likesCount;
          _isSaved = fresh.isSaved ?? false;
          _isReposted = fresh.isReposted ?? false;
          _repostsCount = fresh.repostsCount;
        });
      }
    } catch (_) {}
  }

  void _onPollUpdated(PollData poll) {
    final body = Map<String, dynamic>.from(_displayPost.body ?? {});
    body['poll'] = poll.toJson();
    setState(() {
      _displayPost = _displayPost.copyWith(body: body);
    });
  }

  Future<void> _refreshCommentsCount() async {
    try {
      final total = await CommentService.getCommentsTotal(widget.post.id);
      if (mounted) {
        setState(() => _displayCommentsCount = total);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pressController?.dispose();
    super.dispose();
  }

  Future<void> _checkRepostStatus() async {
    try {
      final token = await AuthService.getAccessTokenForApi();
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
      final token = await AuthService.getAccessTokenForApi();
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

  bool get _isRecipe => widget.post.type == 'recipe';

  String get _recipeVisibility =>
      _visibilityOverride ?? widget.post.visibility;

  bool get _canManagePost {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return false;
    if (widget.post.userId == uid) return true;
    return widget.channel.isAdmin ||
        widget.channel.isOwner ||
        widget.channel.isModerator;
  }

  Future<void> _changeRecipeVisibility() async {
    try {
      final status = await SubscriptionService.getSubscriptionStatus();
      if (!mounted) return;
      final newVis = await showChangeRecipeVisibilitySheet(
        context,
        currentVisibility: _recipeVisibility,
        hasCreator: status.hasCreator,
        channelMode: widget.channel.recipeVisibilityMode,
      );
      if (newVis == null || newVis == _recipeVisibility || !mounted) return;

      await ChannelService.updateChannelPost(
        channelId: widget.channelId,
        postId: widget.post.id,
        visibility: newVis,
      );
      if (!mounted) return;
      setState(() => _visibilityOverride = newVis);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVis == 'private'
                ? 'Рецепт теперь только в канале'
                : 'Рецепт опубликован в общем Menu',
          ),
        ),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      if (e.code == 'HAN_CREATOR_REQUIRED') {
        await showCreatorRecipeUpsellSheet(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось изменить видимость'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось изменить видимость'))),
        );
      }
    }
  }

  Future<void> _toggleLike() async {
    if (_isLoading) return;

    final token = await AuthService.getAccessTokenForApi();
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
              userVisibleAuthError(
                e,
                fallback: 'Не удалось поставить лайк',
                authFallback: 'Войдите, чтобы поставить лайк',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleRepost() async {
    if (_isReposting) return;

    // Проверяем авторизацию
    final token = await AuthService.getAccessTokenForApi();
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                userVisibleAuthError(
                  e,
                  fallback: 'Не удалось убрать репост',
                  authFallback: 'Войдите, чтобы убрать репост',
                ),
              ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleAuthError(
                e,
                fallback: 'Не удалось сделать репост',
                authFallback: 'Войдите, чтобы сделать репост',
              ),
            ),
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

  Future<void> _openShareSheet() async {
    await ShareActionSheet.showForPost(
      context,
      post: widget.post,
      onRepostToWall: _toggleRepost,
    );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось сохранить'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Как в ленте: «только что», «N мин назад», «d MMM» и т.д.
  String _formatFeedDate(DateTime date) {
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

  // Используем утилиту для форматирования чисел
  String _formatCount(int count) => NumberFormatter.formatCount(count);

  String _recipeTitle(PostModel post) {
    final body = post.body;
    final nestedRecipe = body?['recipe'];
    final bodyTitle = body?['title']?.toString().trim();
    final translated = body?['translated_title']?.toString().trim();
    final bodyName = body?['name']?.toString().trim();
    final postTitle = post.title?.trim();
    String? nestedTitle;
    if (nestedRecipe is Map<String, dynamic>) {
      nestedTitle = nestedRecipe['title']?.toString().trim();
    }
    if (_isMeaningfulTitle(postTitle)) return postTitle!;
    if (_isMeaningfulTitle(bodyTitle)) return bodyTitle!;
    if (_isMeaningfulTitle(translated)) return translated!;
    if (_isMeaningfulTitle(bodyName)) return bodyName!;
    if (_isMeaningfulTitle(nestedTitle)) return nestedTitle!;
    return 'Рецепт';
  }

  Future<void> _openEditPost() async {
    final cid = widget.post.channelId ?? widget.channelId;
    try {
      Map<String, dynamic>? postData;
      final loaded = await ApiService.getPostById(widget.post.id);
      if (loaded != null) {
        postData = loaded.toJson();
      } else {
        final response = await ChannelService.getChannelPosts(
          channelId: cid,
          limit: 50,
          offset: 0,
        );
        postData = response.posts.firstWhere((p) {
          final rawId = p['id'];
          if (rawId is int) return rawId == widget.post.id;
          if (rawId is num) return rawId.toInt() == widget.post.id;
          return rawId?.toString() == widget.post.id.toString();
        });
      }
      if (!mounted) return;
      await context.push(
        ChannelDetailRoute.postEdit(cid, widget.post.id),
        extra: postData,
      );
      await _reloadDisplayPost();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить пост'))),
        );
      }
    }
  }

  Future<void> _unpromotePost() async {
    try {
      await ChannelService.unpromotePost(widget.post.id);
      if (!mounted) return;
      setState(() => _promotedLocally = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Продвижение снято')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось снять продвижение'))),
        );
      }
    }
  }

  Future<void> _promotePost() async {
    try {
      final status = await SubscriptionService.getSubscriptionStatus();
      if (!status.hasCreator) {
        if (!mounted) return;
        context.push(SubscriptionRoute.pathWithProduct('creator'));
        return;
      }
      await ChannelService.promotePost(widget.post.id);
      if (!mounted) return;
      setState(() => _promotedLocally = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост продвигается в ленте')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось продвинуть'))),
        );
      }
    }
  }

  Future<void> _confirmAndDeletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить пост?'),
        content: const Text(
          'Вы уверены, что хотите удалить этот пост? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ChannelService.deleteChannelPost(
        channelId: widget.post.channelId ?? widget.channelId,
        postId: widget.post.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пост удалён')),
        );
        widget.onPostDeleted?.call();
      }
    } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                userVisibleError(e, fallback: 'Не удалось удалить пост'),
              ),
            ),
          );
        }
    }
  }

  /// Справа внизу: управление постом — владелец/админ/модератор/автор.
  Widget _buildTrailingActions() {
    if (_canManagePost) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, size: 28),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onSelected: (value) async {
          if (value == 'copy') {
            await _copyPostLink();
          } else if (value == 'analytics') {
            context.push(AppAnalyticsRoute.pathWithPostId(widget.post.id));
          } else if (value == 'promote') {
            await _promotePost();
          } else if (value == 'unpromote') {
            await _unpromotePost();
          } else if (value == 'edit') {
            await _openEditPost();
          } else if (value == 'visibility') {
            await _changeRecipeVisibility();
          } else if (value == 'delete') {
            await _confirmAndDeletePost();
          } else if (value == 'save') {
            await _toggleSave();
          }
        },
        itemBuilder: (context) {
          return <PopupMenuEntry<String>>[
            const PopupMenuItem(
              value: 'copy',
              child: Row(
                children: [
                  Icon(Icons.link, size: 20),
                  SizedBox(width: 8),
                  Text('Копировать ссылку'),
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
            if (!widget.post.isPromoted && !_promotedLocally)
              const PopupMenuItem(
                value: 'promote',
                child: Row(
                  children: [
                    Icon(Icons.trending_up, size: 20),
                    SizedBox(width: 8),
                    Text('Продвинуть в ленте'),
                  ],
                ),
              ),
            if (widget.post.isPromoted || _promotedLocally)
              const PopupMenuItem(
                value: 'unpromote',
                child: Row(
                  children: [
                    Icon(Icons.trending_flat, size: 20),
                    SizedBox(width: 8),
                    Text('Снять продвижение'),
                  ],
                ),
              ),
            if (widget.post.channelId != null)
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
            if (_isRecipe)
              const PopupMenuItem(
                value: 'visibility',
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Изменить видимость'),
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
            PopupMenuItem(
              value: 'save',
              child: Row(
                children: [
                  Icon(
                    _isSaved ? Icons.bookmark : Icons.bookmark_border,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(_isSaved ? 'Убрать из сохранённых' : 'Сохранить'),
                ],
              ),
            ),
          ];
        },
      );
    }
    final isAuthor = AuthService.instance.currentUser?.id == widget.post.userId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isAuthor)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (value) {
              if (value == 'report') {
                reportPostWithDialog(context, widget.post.id);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
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
    );
  }

  /// Репост в канал: «Репост», аватар источника, комментарий, полное содержимое оригинала.
  Widget _buildChannelRepostSection(PostModel wrapper) {
    final scheme = Theme.of(context).colorScheme;
    final comment = _channelRepostUserComment(wrapper);

    return FutureBuilder<PostModel?>(
      future: _channelRepostOriginalFuture,
      builder: (context, snap) {
        final orig = snap.data;
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;

        String? sourceAvatarUrl() {
          if (orig == null) return null;
          final u = orig.channel?.avatarUrl ?? orig.author?.avatarUrl;
          if (u == null || u.isEmpty) return null;
          return u;
        }

        String sourceName() {
          if (orig == null) return '';
          return orig.channel?.name ?? orig.author?.name ?? 'Пост';
        }

        void openSource() {
          if (orig == null) return;
          if (orig.channel != null) {
            context.push(ChannelDetailRoute.pathFor(orig.channel!.id));
          } else {
            context.push(ProfileRoute.withUserId(orig.userId));
          }
        }

        final avatarUrl = sourceAvatarUrl();
        final name = sourceName();
        final initial =
            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.repeat, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (orig != null) ...[
                    GestureDetector(
                      onTap: openSource,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.surfaceContainerHighest,
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Репост',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (!loading && orig != null) ...[
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: openSource,
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (comment != null && comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  comment,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
            const SizedBox(height: 8),
            if (!loading && orig == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Builder(
                  builder: (context) {
                    final id = _channelRepostOriginalPostId(wrapper.body);
                    if (id == null) return const SizedBox.shrink();
                    return OutlinedButton.icon(
                      onPressed: () => context.push(PostFeedRoute.pathFor(id)),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Открыть оригинал'),
                    );
                  },
                ),
              )
            else if (orig != null) ...[
              _buildMedia(orig),
              if (orig.type == 'recipe' || _isMeaningfulTitle(orig.title))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    orig.type == 'recipe' ? _recipeTitle(orig) : orig.title!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (orig.description != null &&
                  orig.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    orig.description!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _displayPost;
    final channelRepostOriginalId = _channelRepostOriginalPostId(post.body);

    final shell = PostCardContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (channelRepostOriginalId != null)
            _buildChannelRepostSection(post)
          else ...[
            _buildMedia(post),
            if (post.type == 'recipe' ||
                (post.title != null && post.title!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        post.type == 'recipe'
                            ? _recipeTitle(post)
                            : post.title!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (post.type == 'recipe') ...[
                      const SizedBox(width: 8),
                      RecipeVisibilityBadge(
                        visibility: _recipeVisibility,
                        compact: true,
                      ),
                    ],
                    if (post.isPromoted || _promotedLocally) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Продвижение',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
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
            if (post.linkUrl != null && post.linkUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: InkWell(
                  onTap: () => _openLink(post.linkUrl!),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (post.linkImage != null && post.linkImage!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: post.linkImage!,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                post.linkTitle ?? post.linkUrl!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (post.linkDescription != null &&
                            post.linkDescription!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              post.linkDescription!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (post.linkDomain != null && post.linkDomain!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              post.linkDomain!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (post.poll != null)
              PostPollSection(
                postId: post.id,
                poll: post.poll!,
                canClose: AuthService.instance.currentUser?.id == post.userId,
                onPollUpdated: _onPollUpdated,
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _formatFeedDate(post.publishedAt ?? post.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.visibility_outlined,
                    size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _formatCount(post.viewsCount),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
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
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(_likesCount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.comment_outlined, size: 28),
                      onPressed: () async {
                        final token = await AuthService.getAccessTokenForApi();
                        if (token == null && widget.onCommentTap != null) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Войдите, чтобы оставить комментарий'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                          return;
                        }
                        await widget.onCommentTap?.call();
                        await _refreshCommentsCount();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(_displayCommentsCount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.send_outlined, size: 28),
                      onPressed: _isReposting ? null : _openShareSheet,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
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
                _buildTrailingActions(),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.onCardTap != null &&
        _pressController != null &&
        _scaleAnimation != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _pressController!.forward(),
        onTapUp: (_) {
          _pressController!.reverse();
          widget.onCardTap!();
        },
        onTapCancel: () => _pressController!.reverse(),
        child: ScaleTransition(
          scale: _scaleAnimation!,
          child: shell,
        ),
      );
    }

    return shell;
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
          context.push(ChannelDetailRoute.post(post.channelId!, post.id));
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
                imageUrl = ServerConfig.resolveMediaUrl(imageUrl);
              }
            } catch (e) {
              // Изображение не найдено
            }
          }

          // Собираем данные рецепта из body
          final recipeData = <String, dynamic>{
            'id': post.id, // Используем ID поста как ID рецепта
            'title': _recipeTitle(post),
            'image': imageUrl,
            'ingredients': body['ingredients'] ?? [],
            'steps': body['steps'] ?? [],
            'usedIngredientCount': (body['ingredients'] as List?)?.length ?? 0,
            'calories': body['calories'],
            'source': body['source']?.toString() ?? 'channel',
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
