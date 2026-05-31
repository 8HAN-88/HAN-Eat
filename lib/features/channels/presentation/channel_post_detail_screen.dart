// Экран детального просмотра поста из канала
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/app_router.dart';
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../screens/detail_page.dart';
import '../../../services/api_service.dart';
import '../../../services/channel_service.dart';
import '../../../services/favorites_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/image_url_helper.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../widgets/app_empty_state.dart';

int? _repostOriginalPostIdFromBody(Map<String, dynamic>? body) {
  final raw = body?['repost_original_post_id'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

String? _channelRepostUserComment(PostModel post) {
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

bool _isMeaningfulTitle(String? s) {
  if (s == null) return false;
  final t = s.trim();
  return t.isNotEmpty && t != '.' && t != '…' && t != '...';
}

class ChannelPostDetailScreen extends ConsumerStatefulWidget {
  final int channelId;
  final int postId;

  const ChannelPostDetailScreen({
    super.key,
    required this.channelId,
    required this.postId,
  });

  @override
  ConsumerState<ChannelPostDetailScreen> createState() =>
      _ChannelPostDetailScreenState();
}

class _ChannelPostDetailScreenState
    extends ConsumerState<ChannelPostDetailScreen> {
  PostModel? _post;
  Object? _loadError;

  /// Оригинал для поста «репост в канал» (обёртка в body.repost_original_post_id).
  PostModel? _originalPost;
  bool _isLoading = true;
  bool _recipeScreenOpened = false;

  PostModel get _displayPost => _originalPost ?? _post!;

  String _recipeTitle(Map<String, dynamic>? body) {
    final nestedRecipe = body?['recipe'];
    final postTitle = _displayPost.title?.trim();
    final bodyTitle = body?['title']?.toString().trim();
    final translated = body?['translated_title']?.toString().trim();
    final bodyName = body?['name']?.toString().trim();
    String? nestedTitle;
    if (nestedRecipe is Map<String, dynamic>) {
      nestedTitle = nestedRecipe['title']?.toString().trim();
    }
    if (_isMeaningfulTitle(postTitle)) return postTitle!;
    if (bodyTitle != null && bodyTitle.isNotEmpty) return bodyTitle;
    if (translated != null && translated.isNotEmpty) return translated;
    if (bodyName != null && bodyName.isNotEmpty) return bodyName;
    if (nestedTitle != null && nestedTitle.isNotEmpty) return nestedTitle;
    return 'Рецепт';
  }

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      PostModel? parsed = await ApiService.getPostById(widget.postId);

      if (parsed == null) {
        final response = await ChannelService.getChannelPosts(
          channelId: widget.channelId,
          limit: 50,
          offset: 0,
        );
        Map<String, dynamic>? postData;
        try {
          postData = response.posts.firstWhere((p) {
            final rawId = p['id'];
            if (rawId is int) return rawId == widget.postId;
            if (rawId is num) return rawId.toInt() == widget.postId;
            final idStr = rawId?.toString() ?? '';
            final numeric = idStr.replaceFirst(
              RegExp(r'^(spoonacular_|user_|channel_)'),
              '',
            );
            return int.tryParse(numeric) == widget.postId;
          });
        } catch (_) {
          postData = null;
        }
        if (postData != null) {
          parsed = PostModel.fromJson(postData);
        }
      }

      if (parsed == null) {
        throw Exception('Пост не найден');
      }

      final postChannelId = parsed.channelId ?? parsed.communityId;
      if (postChannelId != null && postChannelId != widget.channelId) {
        throw Exception('Пост не найден в этом канале');
      }

      final origId = _repostOriginalPostIdFromBody(parsed.body);
      PostModel? orig;
      if (origId != null) {
        orig = await ApiService.getPostById(origId);
      }
      if (!mounted) return;
      setState(() {
        _post = parsed;
        _originalPost = orig;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Пост')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_post == null) {
      if (_loadError != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Пост')),
          body: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить',
            subtitle: userVisibleError(
              _loadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: _loadPost,
              child: const Text('Повторить'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Пост')),
        body: const AppEmptyState(
          icon: Icons.article_outlined,
          title: 'Пост не найден',
          subtitle: 'Возможно, он удалён или недоступен',
        ),
      );
    }

    // Если пост (или оригинал репоста в канал) — рецепт, открываем экран рецепта
    if (_displayPost.type == 'recipe') {
      // Открываем экран рецепта сразу после загрузки (только один раз)
      if (!_recipeScreenOpened) {
        _recipeScreenOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openRecipeScreen();
          }
        });
      }
      // Показываем экран загрузки пока рецепт открывается
      return Scaffold(
        appBar: AppBar(
          title: const Text('Рецепт'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final origId = _repostOriginalPostIdFromBody(_post!.body);
    final repostMissingOriginal = origId != null && _originalPost == null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: _buildImageHeader(),
          ),
          if (origId != null) SliverToBoxAdapter(child: _buildRepostBanner()),
          if (repostMissingOriginal)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Не удалось загрузить оригинальный пост',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push(PostFeedRoute.pathFor(origId)),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Открыть оригинал'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: _buildPostContent(),
            ),
        ],
      ),
    );
  }

  Widget _buildRepostBanner() {
    final scheme = Theme.of(context).colorScheme;
    final wrapper = _post!;
    final orig = _originalPost;
    final comment = _channelRepostUserComment(wrapper);

    String sourceName() {
      if (orig == null) return '';
      return orig.channel?.name ?? orig.author?.name ?? 'Пост';
    }

    String? avatarUrl() {
      if (orig == null) return null;
      final u = orig.channel?.avatarUrl ?? orig.author?.avatarUrl;
      if (u == null || u.isEmpty) return null;
      return u;
    }

    void openSource() {
      if (orig == null) return;
      if (orig.channel != null) {
        context.push(ChannelDetailRoute.pathFor(orig.channel!.id));
      } else {
        context.push(ProfileRoute.withUserId(orig.userId));
      }
    }

    final name = sourceName();
    final url = avatarUrl();
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.repeat, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          if (orig != null)
            GestureDetector(
              onTap: openSource,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: scheme.surfaceContainerHighest,
                backgroundImage:
                    url != null ? CachedNetworkImageProvider(url) : null,
                child: url == null
                    ? Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
            ),
          if (orig != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Репост',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (orig != null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: openSource,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (comment != null && comment.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    comment,
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageHeader() {
    final body = _displayPost.body;
    final media = body?['media'] as List<dynamic>?;
    final imageUrls = <String>[];
    if (media != null) {
      for (final item in media) {
        if (item is! Map) continue;
        if (item['type'] != 'image') continue;
        final url = item['url']?.toString().trim() ?? '';
        if (url.isNotEmpty) {
          imageUrls.add(ServerConfig.resolveMediaUrl(url));
        }
      }
    }

    if (imageUrls.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.article_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    if (imageUrls.length > 1) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 56, 8, 8),
            child: TelegramPhotoGrid(
              imageUrls: imageUrls,
              maxHeight: 280,
              enableFullscreen: true,
            ),
          ),
        ),
      );
    }

    final optimizedUrl = getOptimizedImageUrl(imageUrls.first);
    return CachedNetworkImage(
      imageUrl: optimizedUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[300],
        child: const Icon(Icons.error_outline),
      ),
    );
  }

  Widget _buildPostContent() {
    final p = _displayPost;
    final showTitle = p.type == 'recipe' || _isMeaningfulTitle(p.title);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Text(
              p.type == 'recipe' ? _recipeTitle(p.body) : p.title!,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (showTitle) const SizedBox(height: 16),
          if (p.description != null && p.description!.trim().isNotEmpty)
            Text(
              p.description!,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
              ),
            ),
          if (p.description != null && p.description!.trim().isNotEmpty)
            const SizedBox(height: 24),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                _formatDate(p.publishedAt ?? p.createdAt),
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (p.tags != null && p.tags!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${p.tags!.length} тегов',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          if (p.tags != null && p.tags!.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: p.tags!.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _openRecipeScreen() {
    // Преобразуем PostModel в Recipe для DetailPage
    final body = _displayPost.body;
    final ingredientsList = body?['ingredients'] as List<dynamic>? ?? [];
    final stepsList = body?['steps'] as List<dynamic>? ?? [];

    // Преобразуем ингредиенты в List<String>
    final ingredients = ingredientsList.map((e) => e.toString()).toList();

    // Преобразуем шаги в List<Map<String, dynamic>>
    final steps = stepsList.asMap().entries.map((entry) {
      final step = entry.value;
      if (step is Map<String, dynamic>) {
        // Убеждаемся, что есть правильные поля
        final imageValue = step['image'] ?? step['image_url'];
        final imageStr = imageValue != null
            ? (imageValue is String ? imageValue : imageValue.toString())
            : null;
        // Проверяем, что изображение не пустое и не 'null'
        final finalImage =
            (imageStr != null && imageStr.isNotEmpty && imageStr != 'null')
                ? imageStr
                : null;
        return {
          'number': step['number'] ?? entry.key + 1,
          'step': step['step'] ?? step['text'] ?? step['instruction'] ?? '',
          'image': finalImage,
          'image_url': finalImage, // Дублируем для совместимости
        };
      } else if (step is String) {
        return {
          'number': entry.key + 1,
          'step': step,
          'image': null,
        };
      } else {
        return {
          'number': entry.key + 1,
          'step': step.toString(),
          'image': null,
        };
      }
    }).toList();

    final recipe = Recipe(
      id: _displayPost.id,
      title: _recipeTitle(body),
      image: _getImageUrl(),
      usedIngredientCount: ingredients.length,
      ingredients: ingredients,
      steps: steps,
      calories: body?['calories'] as int?,
      author: _displayPost.author?.name,
      source: 'channel',
    );

    // Проверяем, находится ли рецепт в избранном
    final isFavorite =
        FavoritesService.instance.isFavorite(recipe.id.toString());

    // Открываем экран рецепта
    // Используем push, и при возврате сразу закрываем этот экран, чтобы попасть на канал
    if (mounted) {
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (context) => DetailPage(
            recipe: recipe,
            isFavorite: isFavorite,
            onToggle: () {
              FavoritesService.instance.toggleFavorite(recipe.id.toString());
            },
          ),
        ),
      )
          .then((_) {
        // Когда возвращаемся из DetailPage, сразу закрываем этот экран (ChannelPostDetailScreen)
        // чтобы пользователь попал сразу на канал, минуя экран загрузки
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  String? _getImageUrl() {
    final body = _displayPost.body;
    final media = body?['media'] as List<dynamic>?;
    if (media != null && media.isNotEmpty) {
      try {
        final imageMedia = media.firstWhere((m) => m['type'] == 'image');
        final url = imageMedia['url'] as String?;
        // Используем оптимизированную версию если доступна
        return url != null
            ? ServerConfig.resolveMediaUrl(getOptimizedImageUrl(url))
            : null;
      } catch (e) {
        return null;
      }
    }
    return null;
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
        return DateFormat('d MMM yyyy', 'ru').format(date);
      } catch (e) {
        return DateFormat('d MMM yyyy').format(date);
      }
    }
  }
}
