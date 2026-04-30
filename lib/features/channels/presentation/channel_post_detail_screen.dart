// Экран детального просмотра поста из канала
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../models/post_model.dart';
import '../../../models/recipe.dart';
import '../../../screens/detail_page.dart';
import '../../../services/channel_service.dart';
import '../../../services/favorites_service.dart';
import '../../../utils/image_url_helper.dart';

class ChannelPostDetailScreen extends ConsumerStatefulWidget {
  final int channelId;
  final int postId;
  
  const ChannelPostDetailScreen({
    Key? key,
    required this.channelId,
    required this.postId,
  }) : super(key: key);
  
  @override
  ConsumerState<ChannelPostDetailScreen> createState() => _ChannelPostDetailScreenState();
}

class _ChannelPostDetailScreenState extends ConsumerState<ChannelPostDetailScreen> {
  PostModel? _post;
  bool _isLoading = true;
  bool _recipeScreenOpened = false;
  
  @override
  void initState() {
    super.initState();
    _loadPost();
  }
  
  Future<void> _loadPost() async {
    setState(() => _isLoading = true);
    
    try {
      // Загружаем посты канала и находим нужный
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 50,
        offset: 0,
      );
      
      Map<String, dynamic>? postData;
      try {
        final foundPost = response.posts.firstWhere(
          (p) => p['id'] == widget.postId,
        );
        postData = foundPost as Map<String, dynamic>;
      } catch (e) {
        postData = null;
      }
      
      if (postData != null) {
        setState(() {
          _post = PostModel.fromJson(postData!);
        });
      } else {
        throw Exception('Пост не найден');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки поста: $e')),
        );
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
      return Scaffold(
        appBar: AppBar(title: const Text('Пост')),
        body: const Center(child: Text('Пост не найден')),
      );
    }
    
    // Если пост - рецепт, открываем экран рецепта
    if (_post!.type == 'recipe') {
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
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: _buildImageHeader(),
          ),
          SliverToBoxAdapter(
            child: _buildPostContent(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImageHeader() {
    final body = _post!.body;
    final media = body?['media'] as List<dynamic>?;
    String? imageUrl;
    if (media != null && media.isNotEmpty) {
      try {
        final imageMedia = media.firstWhere((m) => m['type'] == 'image');
        imageUrl = imageMedia['url'] as String?;
      } catch (e) {
        imageUrl = null;
      }
    }
    
    if (imageUrl == null) {
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
    
    // Используем helper для получения оптимального URL (medium версия если доступна)
    final optimizedUrl = getOptimizedImageUrl(imageUrl as String);
    
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          if (_post!.title != null && _post!.title!.isNotEmpty)
            Text(
              _post!.title!,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 16),
          // Описание
          if (_post!.description != null && _post!.description!.isNotEmpty)
            Text(
              _post!.description!,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
              ),
            ),
          const SizedBox(height: 24),
          // Метаданные
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                _formatDate(_post!.publishedAt ?? _post!.createdAt),
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (_post!.tags != null && _post!.tags!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${_post!.tags!.length} тегов',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          // Теги
          if (_post!.tags != null && _post!.tags!.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _post!.tags!.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
  
  void _openRecipeScreen() {
    // Преобразуем PostModel в Recipe для DetailPage
    final body = _post!.body;
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
        final finalImage = (imageStr != null && imageStr.isNotEmpty && imageStr != 'null') 
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
    
    // Создаем Recipe из данных поста
    final recipe = Recipe(
      id: _post!.id,
      title: _post!.title ?? 'Рецепт',
      image: _getImageUrl(),
      usedIngredientCount: ingredients.length,
      ingredients: ingredients,
      steps: steps,
      calories: body?['calories'] as int?,
      author: _post!.author?.name,
      source: 'channel',
    );
    
    // Проверяем, находится ли рецепт в избранном
    final isFavorite = FavoritesService.instance.isFavorite(recipe.id.toString());
    
    // Открываем экран рецепта
    // Используем push, и при возврате сразу закрываем этот экран, чтобы попасть на канал
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DetailPage(
            recipe: recipe,
            isFavorite: isFavorite,
            onToggle: () {
              FavoritesService.instance.toggleFavorite(recipe.id.toString());
            },
          ),
        ),
      ).then((_) {
        // Когда возвращаемся из DetailPage, сразу закрываем этот экран (ChannelPostDetailScreen)
        // чтобы пользователь попал сразу на канал, минуя экран загрузки
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }
  
  String? _getImageUrl() {
    final body = _post!.body;
    final media = body?['media'] as List<dynamic>?;
    if (media != null && media.isNotEmpty) {
      try {
        final imageMedia = media.firstWhere((m) => m['type'] == 'image');
        final url = imageMedia['url'] as String?;
        // Используем оптимизированную версию если доступна
        return url != null ? getOptimizedImageUrl(url) : null;
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

