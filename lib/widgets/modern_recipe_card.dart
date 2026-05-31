import 'package:flutter/material.dart';
import 'recipe_network_image.dart';
import '../models/recipe.dart';
import '../services/comment_service.dart';
import '../services/recipe_comments_service.dart';
import '../services/recipe_interaction_stats.dart';
import '../services/server_config.dart';
import '../utils/recipe_nutrition.dart';
import '../models/meal_plan.dart';
import '../services/meal_plan_service.dart';
import '../core/theme/app_card_decorations.dart';
import '../features/subscription/subscription_copy.dart';

class ModernRecipeCard extends StatefulWidget {
  final Recipe recipe;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;
  final bool favoritesLoading;

  /// Ширина / высота зоны превью ([AspectRatio]); по умолчанию портрет 4:5.
  final double imageAspectRatio;

  /// Плотная вёрстка блока под превью (сетка «Меню»): меньше отступов между метриками.
  final bool compact;

  /// Показывать числа калорий и БЖУ (подписчики). Иначе только подписи + «Pro».
  final bool showNutritionValues;

  /// Скрыть кнопку «в избранное» (гость без входа).
  final bool showFavoriteButton;

  const ModernRecipeCard({
    super.key,
    required this.recipe,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
    this.favoritesLoading = false,
    this.imageAspectRatio = 4 / 5,
    this.compact = false,
    this.showNutritionValues = true,
    this.showFavoriteButton = true,
  });

  @override
  State<ModernRecipeCard> createState() => _ModernRecipeCardState();
}

class _ModernRecipeCardState extends State<ModernRecipeCard> {
  double? _resolvedRating;
  int _resolvedRatingCount = 0;
  int? _resolvedCommentCount;

  static final Map<String, double> _ratingCache = <String, double>{};
  static final Map<String, int> _ratingCountCache = <String, int>{};
  static final Map<String, int> _commentCountCache = <String, int>{};
  static final Set<String> _ratingInFlight = <String>{};

  String get _recipeRatingKey {
    final source = widget.recipe.source ?? 'spoonacular';
    return '$source:${widget.recipe.id}';
  }

  bool get _canLoadRemoteRating {
    final src = widget.recipe.source;
    return src == null || src == 'spoonacular' || src == 'user' || src == 'channel';
  }

  @override
  void initState() {
    super.initState();
    _hydrateRatingFromCache();
    _ensureRatingLoaded();
  }

  @override
  void didUpdateWidget(ModernRecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe.id != widget.recipe.id ||
        oldWidget.recipe.source != widget.recipe.source) {
      _hydrateRatingFromCache();
      _ensureRatingLoaded();
    }
  }

  static const Map<String, String> _recipeImageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  void _hydrateRatingFromCache() {
    final key = _recipeRatingKey;
    final pushed = RecipeInteractionStats.snapshot(
      widget.recipe.source ?? 'spoonacular',
      widget.recipe.id,
    );
    if (pushed != null) {
      _resolvedRating = pushed.avgRating;
      _resolvedRatingCount = pushed.ratingCount;
      _resolvedCommentCount = pushed.commentCount;
      _ratingCache[key] = pushed.avgRating;
      _ratingCountCache[key] = pushed.ratingCount;
      _commentCountCache[key] = pushed.commentCount;
      return;
    }
    _resolvedRating = _ratingCache[key];
    _resolvedRatingCount = _ratingCountCache[key] ?? 0;
    _resolvedCommentCount = _commentCountCache[key];
  }

  Future<void> _ensureRatingLoaded() async {
    if (!_canLoadRemoteRating || widget.recipe.rating != null) return;

    final key = _recipeRatingKey;
    if (_ratingCache.containsKey(key) || _ratingInFlight.contains(key)) return;
    _ratingInFlight.add(key);
    try {
      final ratingData = (widget.recipe.source == null || widget.recipe.source == 'spoonacular')
          ? await RecipeCommentsService.getRecipeRating(widget.recipe.id.toString())
          : await CommentService.getPostRating(widget.recipe.id);
      final rating = (ratingData['rating'] as num?)?.toDouble() ?? 0.0;
      final count = (ratingData['count'] as int?) ?? 0;
      _ratingCache[key] = rating;
      _ratingCountCache[key] = count;
      if (mounted && key == _recipeRatingKey) {
        setState(() {
          _resolvedRating = rating;
          _resolvedRatingCount = count;
          _resolvedCommentCount = _commentCountCache[key];
        });
      }
    } catch (_) {
      // ignore transient rating loading errors for card UI
    } finally {
      _ratingInFlight.remove(key);
    }
  }

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
      return '$estimatedMinutes мин';
    } else if (estimatedMinutes < 60) {
      return '$estimatedMinutes мин';
    } else {
      final hours = estimatedMinutes ~/ 60;
      final minutes = estimatedMinutes % 60;
      return minutes > 0 ? '$hoursч $minutesм' : '$hoursч';
    }
  }

  /// Аватар канала или автора поста (стена); иначе иконка ресторана (например Spoonacular).
  Widget _buildPublisherAvatar(ThemeData theme) {
    const size = 36.0;
    final urlRaw = widget.recipe.authorAvatar?.trim();
    final authorLabel = widget.recipe.author?.trim();
    final src = widget.recipe.source?.toLowerCase();
    final isWallOrChannel = src == 'user' || src == 'channel';
    // Инициал только от имени канала/автора из API — не от названия блюда (иначе кажутся «случайные» буквы).
    final labelForInitial =
        (authorLabel != null && authorLabel.isNotEmpty) ? authorLabel : null;

    Widget letterOrFork() {
      // Показываем инициал, если явно user/channel или в ответе есть имя без source (устаревший кэш API).
      final canShowInitial = labelForInitial != null &&
          labelForInitial.isNotEmpty &&
          (isWallOrChannel || src == null || src.isEmpty);
      if (canShowInitial) {
        final ch = labelForInitial.characters.first;
        return ColoredBox(
          color: Colors.white,
          child: Center(
            child: Text(
              ch.toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      return ColoredBox(
        color: Colors.white,
        child: Icon(
          Icons.restaurant_menu,
          color: theme.colorScheme.primary,
          size: 20,
        ),
      );
    }

    Widget clipped(Widget child) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: child),
      );
    }

    if (urlRaw != null && urlRaw.isNotEmpty) {
      final displayUrl = ServerConfig.resolvePublisherAvatarUrl(urlRaw);
      return clipped(
        Image.network(
          displayUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          headers: _recipeImageHeaders,
          errorBuilder: (_, __, ___) => letterOrFork(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return ColoredBox(
              color: Colors.white,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return clipped(letterOrFork());
  }

  /// Превью с оверлеями (аватар, избранное, видео).
  Widget _buildPreviewStack(ThemeData theme) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: widget.imageAspectRatio,
          child: _buildImageOrVideo(theme),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildPublisherAvatar(theme),
          ),
        ),
        if (widget.recipe.videoUrl != null && widget.recipe.videoUrl!.isNotEmpty)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
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
        if (widget.showFavoriteButton)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.white.withValues(alpha: 0.9),
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
                          widget.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color:
                              widget.isFavorite ? Colors.red : Colors.grey,
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Текст и метрики; при [fillToCellBottom] нижняя строка прижата к низу ячейки сетки.
  Widget _buildDetailsPanel(ThemeData theme, String title, {required bool fillToCellBottom}) {
    final pad = widget.compact
        ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
        : const EdgeInsets.fromLTRB(12, 12, 12, 12);

    final body = <Widget>[
      Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: widget.compact ? 15 : 16,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: widget.compact ? 6 : 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DetailItem(
              icon: Icons.access_time,
              label: 'Время',
              value: _getCookingTime(),
              color: theme.colorScheme.primary,
              dense: widget.compact,
            ),
          ),
          SizedBox(width: widget.compact ? 6 : 8),
          Expanded(
            child: _DetailItem(
              icon: Icons.speed,
              label: 'Сложность',
              value: _getDifficulty(),
              color: _getDifficultyColor(_getDifficulty()),
              dense: widget.compact,
            ),
          ),
        ],
      ),
      SizedBox(height: widget.compact ? 4 : 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DetailItem(
              icon: Icons.local_fire_department,
              label: 'Калории',
              value: widget.showNutritionValues
                  ? (widget.recipe.calories != null
                      ? '${widget.recipe.calories} ккал'
                      : '—')
                  : SubscriptionCopy.nutritionLockedValue,
              color: Colors.orange,
              dense: widget.compact,
              valueLocked: !widget.showNutritionValues,
            ),
          ),
          SizedBox(width: widget.compact ? 6 : 8),
          Expanded(
            child: _DetailItem(
              icon: Icons.eco,
              label: 'Углеводы',
              value: widget.showNutritionValues
                  ? (_getCarbs() != null
                      ? '${_getCarbs()!.toStringAsFixed(1)} г'
                      : '—')
                  : SubscriptionCopy.nutritionLockedValue,
              color: Colors.green,
              dense: widget.compact,
              valueLocked: !widget.showNutritionValues,
            ),
          ),
        ],
      ),
      SizedBox(height: widget.compact ? 4 : 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DetailItem(
              icon: Icons.opacity,
              label: 'Жиры',
              value: widget.showNutritionValues
                  ? (_getFat() != null
                      ? '${_getFat()!.toStringAsFixed(1)} г'
                      : '—')
                  : SubscriptionCopy.nutritionLockedValue,
              color: Colors.yellow.shade700,
              dense: widget.compact,
              valueLocked: !widget.showNutritionValues,
            ),
          ),
          SizedBox(width: widget.compact ? 6 : 8),
          Expanded(
            child: _DetailItem(
              icon: Icons.fitness_center,
              label: 'Белки',
              value: widget.showNutritionValues
                  ? (_getProtein() != null
                      ? '${_getProtein()!.toStringAsFixed(1)} г'
                      : '—')
                  : SubscriptionCopy.nutritionLockedValue,
              color: Colors.blue,
              dense: widget.compact,
              valueLocked: !widget.showNutritionValues,
            ),
          ),
        ],
      ),
    ];

    if (fillToCellBottom) {
      body.add(const Spacer());
    } else {
      body.add(SizedBox(height: widget.compact ? 4 : 8));
    }
    body.add(_buildBottomStats(theme));

    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fillToCellBottom ? MainAxisSize.max : MainAxisSize.min,
        children: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Всегда используем перевод если он есть (из настроек)
    final title = widget.recipe.translatedTitle?.isNotEmpty == true
        ? widget.recipe.translatedTitle!
        : widget.recipe.title;

    final preview = _buildPreviewStack(theme);

    final radius = AppCardDecorations.defaultRadius;
    return ListenableBuilder(
      listenable: RecipeInteractionStats.revision,
      builder: (context, _) {
        _hydrateRatingFromCache();
        return Container(
      decoration: AppCardDecorations.elevated(theme, radius: radius),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(radius),
        child: widget.compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  preview,
                  Expanded(
                    child: _buildDetailsPanel(theme, title, fillToCellBottom: true),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  preview,
                  _buildDetailsPanel(theme, title, fillToCellBottom: false),
                ],
              ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildBottomStats(ThemeData theme) {
    final rating = (widget.recipe.rating ?? _resolvedRating ?? 0).clamp(0, 5).toDouble();
    final likesCount = widget.recipe.likesCount ?? 0;
    final c = widget.compact;
    final iconS = c ? 13.0 : 14.0;
    final fontS = c ? 11.0 : 12.0;

    final recipeIdStr = widget.recipe.id.toString();

    Widget statsRow(int mealPlanDisplayCount) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Лайки и план питания (слева)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite,
                size: iconS,
                color: Colors.red,
              ),
              SizedBox(width: c ? 3 : 4),
              Text(
                '$likesCount',
                style: TextStyle(
                  fontSize: fontS,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_resolvedCommentCount != null) ...[
                SizedBox(width: c ? 6 : 8),
                Icon(
                  Icons.comment_outlined,
                  size: iconS,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: c ? 3 : 4),
                Text(
                  '${_resolvedCommentCount!}',
                  style: TextStyle(
                    fontSize: fontS,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(width: c ? 6 : 8),
              Icon(
                Icons.calendar_today,
                size: iconS,
                color: theme.colorScheme.primary,
              ),
              SizedBox(width: c ? 3 : 4),
              Text(
                '$mealPlanDisplayCount',
                style: TextStyle(
                  fontSize: fontS,
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
                  return Icon(
                    Icons.star,
                    size: iconS,
                    color: Colors.amber,
                  );
                } else if (rating > starIndex - 1) {
                  return Icon(
                    Icons.star_half,
                    size: iconS,
                    color: Colors.amber,
                  );
                } else {
                  return Icon(
                    Icons.star_border,
                    size: iconS,
                    color: Colors.amber,
                  );
                }
              }),
              SizedBox(width: c ? 3 : 4),
              Text(
                _resolvedRatingCount > 0 || widget.recipe.rating != null
                    ? rating.toStringAsFixed(1)
                    : '—',
                style: TextStyle(
                  fontSize: fontS,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (_resolvedRatingCount > 0) ...[
                SizedBox(width: c ? 2 : 4),
                Text(
                  '($_resolvedRatingCount)',
                  style: TextStyle(
                    fontSize: fontS - 1,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    int countFromPlan(List<MealPlanEntry> entries) {
      return entries.where((e) => e.recipe.id == recipeIdStr).length;
    }

    try {
      return ValueListenableBuilder<List<MealPlanEntry>>(
        valueListenable: MealPlanService.instance.allEntries,
        builder: (context, entries, _) {
          final fromPlan = countFromPlan(entries);
          final apiFallback = widget.recipe.mealPlanCount ?? 0;
          // Реальные слоты в плане пользователя; если API когда-нибудь отдаст агрегат — показываем при отсутствии локальных данных.
          final display = fromPlan > 0 ? fromPlan : apiFallback;
          return statsRow(display);
        },
      );
    } catch (_) {
      return statsRow(widget.recipe.mealPlanCount ?? 0);
    }
  }

  Widget _buildImageOrVideo(ThemeData theme) {
    // Приоритет: videoThumbnail > image > sourceImage
    final imageUrl = widget.recipe.videoThumbnail ?? widget.recipe.image ?? widget.recipe.sourceImage;
    
    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.trim().isNotEmpty) {
      return RecipeNetworkImage(
        rawUrl: imageUrl,
        profile: RecipeImageProfile.card,
        fit: BoxFit.cover,
        cacheKey: 'card:${widget.recipe.id}:${widget.recipe.source ?? "sp"}',
        placeholder: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: _buildPlaceholderImage(theme),
      );
    }
    
    return _buildPlaceholderImage(theme);
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

  double? _getFat() => parseNutritionFat(widget.recipe.nutrition);

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
  final bool dense;
  final bool valueLocked;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.dense = false,
    this.valueLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelSize = dense ? 10.0 : 11.0;
    final valueSize = dense ? 12.0 : 13.0;
    final iconSize = dense ? 13.0 : 14.0;
    final gap = dense ? 2.0 : 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(width: dense ? 3 : 4),
            Text(
              label,
              style: TextStyle(
                fontSize: labelSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            if (valueLocked) ...[
              Icon(
                Icons.lock_outline,
                size: valueSize + 1,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: dense ? 2 : 4),
            ],
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w600,
                  color: valueLocked
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}



