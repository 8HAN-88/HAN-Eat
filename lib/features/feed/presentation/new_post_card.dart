// Новая карточка поста для нового API
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../models/post.dart' show PollData;
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../services/auth_service.dart';
import '../../../services/favorites_service.dart';
import '../../../services/recipe_comments_service.dart';
import '../../../services/comment_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../screens/detail_page.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/post_card_container.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../services/server_config.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/post_poll_section.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/api_service.dart';
import '../../../services/post_service.dart';
import '../../../services/feed_cache_service.dart';
import 'package:url_launcher/url_launcher.dart';

int? _repostOriginalPostIdFromBody(Map<String, dynamic>? body) {
  final raw = body?['repost_original_post_id'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

String? _channelRepostUserCommentFromPost(PostModel post) {
  final body = post.body;
  final fromBody = body?['repost_to_channel_comment'];
  if (fromBody is String && fromBody.trim().isNotEmpty) return fromBody.trim();
  final desc = post.description;
  if (desc == null || desc.trim().isEmpty) return null;
  final blocks = desc.split(RegExp(r'\n\n+', multiLine: true));
  if (blocks.isEmpty) return null;
  final first = blocks.first.trim();
  if (first.isEmpty || first.startsWith('Репост:')) return null;
  return first;
}

bool _isMeaningfulPostTitle(String? s) {
  if (s == null) return false;
  final t = s.trim();
  return t.isNotEmpty && t != '.' && t != '…' && t != '...';
}

class NewPostCard extends StatefulWidget {
  final PostModel post;
  final Future<void> Function()? onCommentTap;
  final VoidCallback? onAuthorTap;
  /// После удаления поста (обновить список родителя).
  final VoidCallback? onPostDeleted;
  /// Без шапки (аватар, имя, ⋯ сверху) — как карточки в канале; меню переносится в нижний ряд.
  final bool hideFeedHeader;

  const NewPostCard({
    super.key,
    required this.post,
    this.onCommentTap,
    this.onAuthorTap,
    this.onPostDeleted,
    this.hideFeedHeader = false,
  });
  
  @override
  State<NewPostCard> createState() => _NewPostCardState();
}

class _NewPostCardState extends State<NewPostCard> {
  late PostModel _displayPost;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostsCount = 0;
  int _displayCommentsCount = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReposting = false;
  int? _currentUserId;

  int? _feedChannelRepostOrigIdCache;
  Future<PostModel?>? _feedChannelRepostOrigFuture;

  void _syncFeedChannelRepostFuture() {
    final id = _repostOriginalPostIdFromBody(widget.post.body);
    if (id == null) {
      _feedChannelRepostOrigIdCache = null;
      _feedChannelRepostOrigFuture = null;
      return;
    }
    if (_feedChannelRepostOrigIdCache != id) {
      _feedChannelRepostOrigIdCache = id;
      _feedChannelRepostOrigFuture = ApiService.getPostById(id);
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
    _loadCurrentUserId();
    _hydrateSpoonacularCommentsCount();
    _syncFeedChannelRepostFuture();
  }

  @override
  void didUpdateWidget(covariant NewPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _feedChannelRepostOrigIdCache = null;
      _feedChannelRepostOrigFuture = null;
      _displayPost = widget.post;
    } else if (oldWidget.post != widget.post) {
      _displayPost = widget.post;
    }
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    _displayCommentsCount = widget.post.commentsCount;
    _syncFeedChannelRepostFuture();
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
  
  bool get _isAuthor =>
      _currentUserId != null && _currentUserId == _displayPost.userId;

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

  bool get _isSpoonacularRecipePost {
    if (_displayPost.type != 'recipe') return false;
    final body = _displayPost.body;
    if (body == null) return false;
    final source = body['source']?.toString().trim().toLowerCase();
    final nestedRecipe = body['recipe'];
    final nestedSource = nestedRecipe is Map<String, dynamic>
        ? nestedRecipe['source']?.toString().trim().toLowerCase()
        : null;
    return body['spoonacular_recipe_id'] != null ||
        source == 'spoonacular' ||
        nestedSource == 'spoonacular';
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

  int get _spoonacularRecipeIdFromPost {
    final body = widget.post.body;
    if (body == null) return widget.post.id;
    final spoonacularId = body['spoonacular_recipe_id'];
    if (spoonacularId is int) return spoonacularId;
    if (spoonacularId is String) return int.tryParse(spoonacularId) ?? widget.post.id;
    return widget.post.id;
  }

  Future<void> _refreshCommentsCount() async {
    if (_isSpoonacularRecipePost) return;
    try {
      final total = await CommentService.getCommentsTotal(widget.post.id);
      if (mounted) {
        setState(() => _displayCommentsCount = total);
      }
    } catch (_) {}
  }

  Future<void> _hydrateSpoonacularCommentsCount() async {
    if (!_isSpoonacularRecipePost) return;
    try {
      final recipeId = _spoonacularRecipeIdFromPost;
      final comments = await RecipeCommentsService.getComments(recipeId.toString());
      if (!mounted) return;
      setState(() {
        _displayCommentsCount = comments.length;
      });
    } catch (_) {
      // keep existing counter value
    }
  }

  Future<void> _openRecipeFromPost() async {
    final post = widget.post;
    final body = post.body;
    if (body == null) return;
    try {
      int recipeId = post.id;
      if (body['spoonacular_recipe_id'] != null) {
        final spoonacularId = body['spoonacular_recipe_id'];
        final extractedId = spoonacularId is int ? spoonacularId : int.tryParse(spoonacularId.toString());
        if (extractedId != null && extractedId != 0) {
          recipeId = extractedId;
        }
      }

      String? imageUrl = _extractRecipeImageUrl(body);
      if (imageUrl == null || imageUrl.isEmpty) {
        final media = body['media'] as List<dynamic>?;
        if (media != null) {
          for (final m in media) {
            if (m is Map<String, dynamic> && m['type'] == 'image') {
              imageUrl = m['url'] as String?;
              if (imageUrl != null && imageUrl.isNotEmpty) break;
            }
          }
        }
      }

      final ingredients = (body['translated_ingredients'] as List<dynamic>?) ??
          (body['ingredients'] as List<dynamic>?) ??
          [];
      final steps = (body['translated_steps'] as List<dynamic>?) ??
          (body['steps'] as List<dynamic>?) ??
          [];

      final sourceFromBody = body['source']?.toString().trim();
      final nestedRecipe = body['recipe'];
      final nestedSource = nestedRecipe is Map<String, dynamic>
          ? nestedRecipe['source']?.toString().trim()
          : null;
      final hasSpoonacularId = body['spoonacular_recipe_id'] != null;
      final recipeSource = (sourceFromBody?.isNotEmpty == true
              ? sourceFromBody
              : (nestedSource?.isNotEmpty == true ? nestedSource : null)) ??
          (hasSpoonacularId
              ? 'spoonacular'
              : (post.channelId != null || post.communityId != null ? 'channel' : 'user'));

      final recipeData = <String, dynamic>{
        'id': recipeId,
        'title': _recipeTitle(post),
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
        'source': recipeSource,
      };

      final recipe = Recipe.fromJson(recipeData);
      final isFavorite = FavoritesService.instance.isFavorite(recipe.id.toString());
      if (!mounted) return;
      await Navigator.of(context).push(
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
      await _hydrateSpoonacularCommentsCount();
    } catch (_) {
      // ignore navigation parse errors
    }
  }
  
  Future<void> _toggleLike() async {
    if (_isLoading) return;

    if (_isSpoonacularRecipePost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Лайки для Spoonacular-рецептов пока недоступны'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    // Проверяем авторизацию
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleAuthError(
                e,
                fallback: 'Не удалось поставить лайк',
                authFallback: 'Войдите, чтобы поставить лайк',
              ),
            ),
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
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
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
  
  Future<void> _showReportDialog() async {
    await reportPostWithDialog(context, widget.post.id);
  }
  
  Future<void> _onOverflowMenuSelected(String value) async {
    if (value == 'report') {
      _showReportDialog();
    } else if (value == 'edit') {
      if (widget.post.channelId == null) {
        final updated = await context.push<bool>(
          EditProfilePostRoute.pathFor(widget.post.id),
        );
        if (updated == true) await _reloadDisplayPost();
      } else {
        await context.push(
          '/channel/${widget.post.channelId}/post/${widget.post.id}/edit',
          extra: widget.post.toJson(),
        );
        await _reloadDisplayPost();
      }
    } else if (value == 'delete') {
      await _confirmAndDeletePost();
    }
  }

  Future<void> _confirmAndDeletePost() async {
    if (widget.post.channelId != null) return;

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
      await PostService.deletePost(widget.post.id);
      try {
        await FeedCacheService.instance
            .removePostFromCache(widget.post.id.toString());
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост удалён')),
      );
      widget.onPostDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось удалить пост'),
          ),
        ),
      );
    }
  }

  List<PopupMenuEntry<String>> _overflowMenuEntries() {
    return [
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
    ];
  }

  Widget _buildOverflowMenuButton({required double iconSize}) {
    final entries = _overflowMenuEntries();
    if (entries.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: iconSize),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: _onOverflowMenuSelected,
      itemBuilder: (context) => entries,
    );
  }

  /// Репост в канал в ленте: обёртка с [repost_original_post_id] — показываем оригинал.
  Widget _buildFeedChannelRepostBody(PostModel wrapper) {
    final scheme = Theme.of(context).colorScheme;
    final comment = _channelRepostUserCommentFromPost(wrapper);

    return FutureBuilder<PostModel?>(
      future: _feedChannelRepostOrigFuture,
      builder: (context, snap) {
        final orig = snap.data;
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;

        String sourceName(PostModel? o) {
          if (o == null) return '';
          return o.channel?.name ?? o.author?.name ?? 'Пост';
        }

        String? sourceAvatar(PostModel? o) {
          if (o == null) return null;
          final u = o.channel?.avatarUrl ?? o.author?.avatarUrl;
          if (u == null || u.isEmpty) return null;
          return u;
        }

        void openSource(PostModel? o) {
          if (o == null) return;
          if (o.channel != null) {
            context.push('/channel/${o.channel!.id}');
          } else {
            context.push('/profile?userId=${o.userId}');
          }
        }

        final name = sourceName(orig);
        final url = sourceAvatar(orig);
        final initial =
            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child:
                        Icon(Icons.repeat, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  else if (orig != null) ...[
                    GestureDetector(
                      onTap: () => openSource(orig),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.surfaceContainerHighest,
                        backgroundImage: url != null
                            ? CachedNetworkImageProvider(url)
                            : null,
                        child: url == null
                            ? Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 14,
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
                            onTap: () => openSource(orig),
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
            const SizedBox(height: 6),
            if (!loading && orig == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Builder(
                  builder: (context) {
                    final id = _repostOriginalPostIdFromBody(wrapper.body);
                    if (id == null) return const SizedBox.shrink();
                    return OutlinedButton.icon(
                      onPressed: () => context.push('/post/$id'),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Открыть оригинал'),
                    );
                  },
                ),
              )
            else if (orig != null) ...[
              _buildMedia(orig),
              if (orig.type == 'recipe' || _isMeaningfulPostTitle(orig.title))
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
    final post = _displayPost;
    final author = post.author;  // Автор оригинального поста
    final repostedBy = post.repostedBy;  // Тот, кто репостнул
    final channel = post.channel;
    
    // Логика отображения автора:
    // 1. Если пост репостнут - в шапке показываем того, кто репостнул, ниже - оригинального автора
    // 2. Если пост из канала (channelId != null) - показываем канал
    // 3. Иначе - показываем автора поста
    final isRepost = repostedBy != null;
    final isFromChannel = post.channelId != null || post.communityId != null;
    final isFeedChannelRepostWrapper =
        _repostOriginalPostIdFromBody(post.body) != null;
    
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
      debugPrint('🔍 [POST CARD] Rendering channel post ${post.id}, communityId=${post.communityId}, channel=${channel?.name}, repostedBy=${repostedBy?.name}');
    }
    
    // Красивая карточка с тенью и скруглениями
    return PostCardContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Компактная метка репоста (шапка скрыта — иначе репост неотличим от обычного поста)
          if (widget.hideFeedHeader && isRepost)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.repeat,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (originalAuthorIsChannel &&
                              post.channelId != null) {
                            context.push('/channel/${post.channelId}');
                          } else {
                            context.push('/profile?userId=${post.userId}');
                          }
                        },
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage:
                              originalAuthorAvatar != null &&
                                      originalAuthorAvatar.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      originalAuthorAvatar,
                                    )
                                  : null,
                          child:
                              originalAuthorAvatar == null ||
                                      originalAuthorAvatar.isEmpty
                                  ? Text(
                                      (originalAuthorName != null &&
                                              originalAuthorName.isNotEmpty)
                                          ? originalAuthorName[0]
                                              .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                context.push(
                                    '/profile?userId=${repostedBy.id}');
                              },
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Репост · '),
                                    TextSpan(
                                      text: repostedBy.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (repostedBy.comment != null &&
                                repostedBy.comment!.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                repostedBy.comment!.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!widget.hideFeedHeader)
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
                                color: Colors.blue.withValues(alpha: 0.1),
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
                                } else if (!originalAuthorIsChannel) {
                                  // Если оригинальный автор - пользователь, открываем профиль
                                  context.push('/profile?userId=${post.userId}');
                                }
                              },
                              child: originalAuthorAvatar != null
                                  ? CircleAvatar(
                                      radius: 10,
                                      backgroundImage: CachedNetworkImageProvider(originalAuthorAvatar),
                                    )
                                  : CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.grey[400],
                                          child: Text(
                                            originalAuthorName[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                            ),
                            const SizedBox(width: 6),
                            // Имя оригинального автора (кликабельное)
                            GestureDetector(
                              onTap: () {
                                // Если оригинальный автор - канал, открываем канал
                                if (originalAuthorIsChannel && post.channelId != null) {
                                  context.push('/channel/${post.channelId}');
                                } else if (!originalAuthorIsChannel) {
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
                                  color: Colors.blue.withValues(alpha: 0.1),
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
                        if (repostedBy.comment != null &&
                            repostedBy.comment!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            repostedBy.comment!.trim(),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ]
                      // Для постов из каналов показываем описание канала или "Канал"
                      else if (isFromChannel && !isFeedChannelRepostWrapper)
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
                    ],
                  ),
                ),
                _buildOverflowMenuButton(iconSize: 24),
              ],
            ),
          ),
          if (isFeedChannelRepostWrapper)
            _buildFeedChannelRepostBody(post)
          else ...[
            _buildMedia(post),
            if (post.type == 'recipe' || _isMeaningfulPostTitle(post.title))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  post.type == 'recipe' ? _recipeTitle(post) : post.title!,
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
                canClose: _isAuthor,
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
                  _formatDate(post.publishedAt ?? post.createdAt),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.visibility_outlined,
                    size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _formatCount(post.viewsCount),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
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
                    // Комментарий с счетчиком
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.comment_outlined, size: 28),
                          onPressed: () async {
                            if (_isSpoonacularRecipePost) {
                              await _openRecipeFromPost();
                              return;
                            }
                            final token = await AuthService.getAccessTokenForApi();
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
                    // Репост с счетчиком
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
                    if (widget.hideFeedHeader) ...[
                      _buildOverflowMenuButton(iconSize: 28),
                      const SizedBox(width: 4),
                    ],
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

  String _recipeTitle(PostModel post) {
    final body = post.body;
    final nestedRecipe = body?['recipe'];
    final postTitle = post.title?.trim();
    final bodyTitle = body?['title']?.toString().trim();
    final translated = body?['translated_title']?.toString().trim();
    final bodyName = body?['name']?.toString().trim();
    String? nestedTitle;
    if (nestedRecipe is Map<String, dynamic>) {
      nestedTitle = nestedRecipe['title']?.toString().trim();
    }

    if (postTitle != null && postTitle.isNotEmpty) return postTitle;
    if (bodyTitle != null && bodyTitle.isNotEmpty) return bodyTitle;
    if (translated != null && translated.isNotEmpty) return translated;
    if (bodyName != null && bodyName.isNotEmpty) return bodyName;
    if (nestedTitle != null && nestedTitle.isNotEmpty) return nestedTitle;
    return 'Рецепт';
  }
  
  /// Получить прокси URL для изображений Spoonacular (для обхода CORS на веб)
  String _getProxyUrl(String originalUrl) {
    // Для Spoonacular на iOS/Android используем прямой URL (надежнее),
    // а на Web ServerConfig сам переведет на proxy.
    return ServerConfig.resolveRecipeImageUrl(originalUrl);
  }
  
  /// Построить виджет для отображения медиа поста
  Widget _buildMedia(PostModel post) {
    // Получаем медиа из body
    final body = post.body;
    if (body == null) return const SizedBox.shrink();
    
    final media = body['media'] as List<dynamic>?;
    
    // Если media пустой, пытаемся собрать превью из известных полей рецепта.
    List<dynamic>? effectiveMedia = media;
    if (media == null || media.isEmpty) {
      final imageUrl = _extractRecipeImageUrl(body);
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
          
          // Получаем изображение из body (включая nested recipe) или media.
          String? imageUrl = _extractRecipeImageUrl(body);
          
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
                  content: Text('Не удалось открыть рецепт'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
          
          debugPrint('✅ Используем recipeId: $recipeId');
          
          // Используем переведенные данные, если они есть
          final title = _recipeTitle(post);
          final ingredients = (body['translated_ingredients'] as List<dynamic>?) ?? 
                              (body['ingredients'] as List<dynamic>?) ?? [];
          final steps = (body['translated_steps'] as List<dynamic>?) ?? 
                        (body['steps'] as List<dynamic>?) ?? [];
          
          debugPrint('🔍 title: $title, ingredients: ${ingredients.length}, steps: ${steps.length}');
          
          // Собираем данные рецепта из body
          final sourceFromBody = body['source']?.toString().trim();
          final nestedRecipe = body['recipe'];
          final nestedSource = nestedRecipe is Map<String, dynamic>
              ? nestedRecipe['source']?.toString().trim()
              : null;
          final hasSpoonacularId = body['spoonacular_recipe_id'] != null;
          final recipeSource = (sourceFromBody?.isNotEmpty == true
                  ? sourceFromBody
                  : (nestedSource?.isNotEmpty == true ? nestedSource : null)) ??
              (hasSpoonacularId
                  ? 'spoonacular'
                  : (post.channelId != null || post.communityId != null
                      ? 'channel'
                      : 'user'));

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
            'source': recipeSource,
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
                content: Text(
                  userVisibleError(e, fallback: 'Не удалось открыть рецепт'),
                ),
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
    final videos = effectiveMedia.where((m) => m['type'] == 'video').toList();
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

  String? _extractRecipeImageUrl(Map<String, dynamic> body) {
    final directImage = body['image']?.toString();
    if (directImage != null && directImage.trim().isNotEmpty) {
      return directImage.trim();
    }

    final sourceImage = body['source_image']?.toString();
    if (sourceImage != null && sourceImage.trim().isNotEmpty) {
      return sourceImage.trim();
    }

    final nestedRecipe = body['recipe'];
    if (nestedRecipe is Map<String, dynamic>) {
      final nestedImage = nestedRecipe['image']?.toString();
      if (nestedImage != null && nestedImage.trim().isNotEmpty) {
        return nestedImage.trim();
      }

      final nestedSourceImage = nestedRecipe['source_image']?.toString();
      if (nestedSourceImage != null && nestedSourceImage.trim().isNotEmpty) {
        return nestedSourceImage.trim();
      }
    }

    return null;
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

