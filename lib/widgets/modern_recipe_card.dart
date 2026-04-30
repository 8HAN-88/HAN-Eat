import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../utils/image_url_helper.dart';

class ModernRecipeCard extends StatefulWidget {
  final Recipe recipe;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;
  final bool favoritesLoading;

  const ModernRecipeCard({
    super.key,
    required this.recipe,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
    this.favoritesLoading = false,
  });

  @override
  State<ModernRecipeCard> createState() => _ModernRecipeCardState();
}

class _ModernRecipeCardState extends State<ModernRecipeCard> {
  // Убрали загрузку рейтинга, чтобы избежать множественных запросов
  // Используем fallback значение для отображения

  String _getDifficulty() {
    // Определяем сложность на основе количества шагов и ингредиентов
    final stepsCount = widget.recipe.translatedSteps?.isNotEmpty == true 
        ? widget.recipe.translatedSteps!.length 
        : widget.recipe.steps.length;
    final ingredients = widget.recipe.translatedIngredients?.isNotEmpty == true
        ? widget.recipe.translatedIngredients!
        : widget.recipe.ingredients;
    final ingredientsCount = ingredients.length;
    
    if (stepsCount <= 3 && ingredientsCount <= 5) {
      return 'Легко';
    } else if (stepsCount <= 6 && ingredientsCount <= 10) {
      return 'Средне';
    } else {
      return 'Сложно';
    }
  }

  String _getCookingTime() {
    // Примерное время на основе количества шагов
    final stepsCount = widget.recipe.steps.length;
    final estimatedMinutes = stepsCount * 5 + 15; // Базовое время + время на шаги
    
    if (estimatedMinutes < 30) {
      return '${estimatedMinutes} мин';
    } else if (estimatedMinutes < 60) {
      return '${estimatedMinutes} мин';
    } else {
      final hours = estimatedMinutes ~/ 60;
      final minutes = estimatedMinutes % 60;
      return minutes > 0 ? '${hours}ч ${minutes}м' : '${hours}ч';
    }
  }

  double _getRating() {
    // Используем fallback значение, чтобы избежать множественных запросов к API
    // Можно добавить батч-загрузку рейтингов в будущем, если это будет необходимо
    return 4.0 + (widget.recipe.id % 2) * 0.5; // 4.0 или 4.5 звезд
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Всегда используем перевод если он есть (из настроек)
    final title = widget.recipe.translatedTitle?.isNotEmpty == true
        ? widget.recipe.translatedTitle!
        : widget.recipe.title;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Изображение или видео
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: _buildImageOrVideo(theme),
                ),
                // Аватарка автора или иконка Spoonacular
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: widget.recipe.source == 'user' && widget.recipe.authorAvatar != null && widget.recipe.authorAvatar!.isNotEmpty
                        ? CircleAvatar(
                            radius: 18,
                            backgroundImage: NetworkImage(widget.recipe.authorAvatar!),
                            onBackgroundImageError: (_, __) {},
                          )
                        : CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.restaurant_menu,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                  ),
                ),
                // Иконка видео, если есть
                if (widget.recipe.videoUrl != null && widget.recipe.videoUrl!.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_circle_filled,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Видео',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Кнопка избранного
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withOpacity(0.9),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: widget.favoritesLoading ? null : widget.onFavoriteTap,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: widget.favoritesLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: widget.isFavorite ? Colors.red : Colors.grey,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Контент карточки
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Название блюда
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Время приготовления (сверху)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.access_time,
                          label: 'Время',
                          value: _getCookingTime(),
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.speed,
                          label: 'Сложность',
                          value: _getDifficulty(),
                          color: _getDifficultyColor(_getDifficulty()),
                        ),
                      ),
                    ],
                  ),
                  // Калории (слева) и углеводы (справа, над белками)
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.local_fire_department,
                          label: 'Калории',
                          value: widget.recipe.calories != null
                              ? '${widget.recipe.calories} ккал'
                              : '—',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.eco,
                          label: 'Углеводы',
                          value: _getCarbs() != null
                              ? '${_getCarbs()!.toStringAsFixed(1)} г'
                              : '—',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  // Жиры (слева, под калориями) и белки (справа, под углеводами)
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.opacity,
                          label: 'Жиры',
                          value: _getFat() != null
                              ? '${_getFat()!.toStringAsFixed(1)} г'
                              : '—',
                          color: Colors.yellow.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailItem(
                          icon: Icons.fitness_center,
                          label: 'Белки',
                          value: _getProtein() != null
                              ? '${_getProtein()!.toStringAsFixed(1)} г'
                              : '—',
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  // Рейтинг, лайки и план питания (внизу карточки)
                  const SizedBox(height: 8),
                  _buildBottomStats(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStats(ThemeData theme) {
    final rating = widget.recipe.rating ?? _getRating();
    final likesCount = widget.recipe.likesCount ?? 0;
    final mealPlanCount = widget.recipe.mealPlanCount ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Лайки и план питания (слева)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite,
              size: 14,
              color: Colors.red,
            ),
            const SizedBox(width: 4),
            Text(
              '$likesCount',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.calendar_today,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              '$mealPlanCount',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        // Рейтинг со звездочками (справа)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(5, (index) {
              final starIndex = index + 1;
              if (rating >= starIndex) {
                return const Icon(
                  Icons.star,
                  size: 14,
                  color: Colors.amber,
                );
              } else if (rating > starIndex - 1) {
                return const Icon(
                  Icons.star_half,
                  size: 14,
                  color: Colors.amber,
                );
              } else {
                return const Icon(
                  Icons.star_border,
                  size: 14,
                  color: Colors.amber,
                );
              }
            }),
            const SizedBox(width: 4),
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageOrVideo(ThemeData theme) {
    // Приоритет: videoThumbnail > image > sourceImage
    final imageUrl = widget.recipe.videoThumbnail ?? widget.recipe.image ?? widget.recipe.sourceImage;
    
    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.trim().isNotEmpty) {
      // Для Flutter Web используем прокси через бэкенд для обхода CORS
      final proxyUrl = _getProxyUrl(imageUrl);
      
      return Image.network(
        getOptimizedImageUrl(proxyUrl),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('❌ Image load error for $proxyUrl: $error');
          return _buildPlaceholderImage(theme);
        },
      );
    }
    
    return _buildPlaceholderImage(theme);
  }
  
  String _getProxyUrl(String originalUrl) {
    // Для Flutter Web используем прокси через бэкенд для обхода CORS
    // Для других платформ используем оригинальный URL
    if (originalUrl.startsWith('https://img.spoonacular.com') || 
        originalUrl.startsWith('https://spoonacular.com')) {
      // Используем прокси только для Spoonacular изображений
      final baseUrl = '${ApiService.baseUrl}/api/v1';
      final encodedUrl = Uri.encodeComponent(originalUrl);
      final proxyUrl = '$baseUrl/recipes/image-proxy?url=$encodedUrl';
      print('🖼️ Using proxy URL: $proxyUrl');
      return proxyUrl;
    }
    print('🖼️ Using original URL: $originalUrl');
    return originalUrl;
  }

  Widget _buildPlaceholderImage(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          size: 48,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Легко':
        return Colors.green;
      case 'Средне':
        return Colors.orange;
      case 'Сложно':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _hasNutrition() {
    if (widget.recipe.nutrition == null) return false;
    final nutrition = widget.recipe.nutrition!;
    // Проверяем наличие хотя бы одного из БЖУ (теперь они всегда вычисляются)
    // Проверяем не только наличие ключей, но и что значения не null
    final hasProtein = (nutrition['protein'] != null || nutrition['proteins'] != null);
    final hasFat = (nutrition['fat'] != null || nutrition['fats'] != null);
    final hasCarbs = (nutrition['carbs'] != null || nutrition['carbohydrates'] != null || nutrition['carb'] != null);
    return hasProtein || hasFat || hasCarbs;
  }

  double? _getProtein() {
    final nutrition = widget.recipe.nutrition;
    if (nutrition == null) {
      return null;
    }
    
    // Сначала пробуем прямые ключи
    var protein = nutrition['protein'] ?? nutrition['proteins'];
    
    // Если нет, пробуем извлечь из массива nutrients
    if (protein == null) {
      final nutrients = nutrition['nutrients'];
      if (nutrients is List) {
        for (var n in nutrients) {
          if (n is Map) {
            final name = (n['name']?.toString() ?? '').toLowerCase();
            final title = (n['title']?.toString() ?? '').toLowerCase();
            final searchName = title.isNotEmpty ? title : name;
            if (searchName.contains('protein')) {
              final amount = n['amount'];
              if (amount != null) {
                if (amount is num) {
                  protein = amount.toDouble();
                  break;
                } else if (amount is String) {
                  protein = double.tryParse(amount);
                  if (protein != null) break;
                }
              }
            }
          }
        }
      }
    }
    
    if (protein == null) return null;
    
    if (protein is num) return protein.toDouble();
    if (protein is String) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(protein);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }

  double? _getFat() {
    final nutrition = widget.recipe.nutrition;
    if (nutrition == null) {
      return null;
    }
    
    // Сначала пробуем прямые ключи
    var fat = nutrition['fat'] ?? nutrition['fats'];
    
    // Если нет, пробуем извлечь из массива nutrients
    if (fat == null) {
      final nutrients = nutrition['nutrients'];
      if (nutrients is List) {
        for (var n in nutrients) {
          if (n is Map) {
            final name = (n['name']?.toString() ?? '').toLowerCase();
            final title = (n['title']?.toString() ?? '').toLowerCase();
            final searchName = title.isNotEmpty ? title : name;
            if (searchName.contains('fat') && searchName.contains('total')) {
              final amount = n['amount'];
              if (amount != null) {
                if (amount is num) {
                  fat = amount.toDouble();
                  break;
                } else if (amount is String) {
                  fat = double.tryParse(amount);
                  if (fat != null) break;
                }
              }
            }
          }
        }
      }
    }
    
    if (fat == null) return null;
    
    if (fat is num) return fat.toDouble();
    if (fat is String) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(fat);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }

  double? _getCarbs() {
    final nutrition = widget.recipe.nutrition;
    if (nutrition == null) {
      return null;
    }
    
    // Сначала пробуем прямые ключи
    var carbs = nutrition['carbs'] ?? nutrition['carbohydrates'] ?? nutrition['carb'];
    
    // Если нет, пробуем извлечь из массива nutrients
    if (carbs == null) {
      final nutrients = nutrition['nutrients'];
      if (nutrients is List) {
        for (var n in nutrients) {
          if (n is Map) {
            final name = (n['name']?.toString() ?? '').toLowerCase();
            final title = (n['title']?.toString() ?? '').toLowerCase();
            final searchName = title.isNotEmpty ? title : name;
            if ((searchName.contains('carbohydrate') || searchName.contains('carbs') || searchName.contains('carb')) 
                && !searchName.contains('net')) {
              final amount = n['amount'];
              if (amount != null) {
                if (amount is num) {
                  carbs = amount.toDouble();
                  break;
                } else if (amount is String) {
                  carbs = double.tryParse(amount);
                  if (carbs != null) break;
                }
              }
            }
          }
        }
      }
    }
    
    if (carbs == null) return null;
    
    if (carbs is num) return carbs.toDouble();
    if (carbs is String) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(carbs);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}



