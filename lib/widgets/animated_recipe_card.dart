import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../utils/image_url_helper.dart';
import '../utils/recipe_nutrition.dart';

class AnimatedRecipeCard extends StatefulWidget {
  final Recipe recipe;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;
  final bool favoritesLoading;
  final int index; // Для staggered animation

  const AnimatedRecipeCard({
    super.key,
    required this.recipe,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
    this.favoritesLoading = false,
    this.index = 0,
  });

  @override
  State<AnimatedRecipeCard> createState() => _AnimatedRecipeCardState();
}

class _AnimatedRecipeCardState extends State<AnimatedRecipeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.reverse();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.forward();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Всегда используем перевод если он есть (из настроек)
    final title = widget.recipe.translatedTitle?.isNotEmpty == true
        ? widget.recipe.translatedTitle!
        : widget.recipe.title;
    final ingredients = widget.recipe.translatedIngredients?.isNotEmpty == true
        ? widget.recipe.translatedIngredients!
        : widget.recipe.ingredients;
    final subtitle = widget.recipe.summary?.isNotEmpty == true
        ? widget.recipe.summary!
        : '${ingredients.take(3).join(', ')}...';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (widget.index * 50)),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Card(
            elevation: _isPressed ? 2 : 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surface,
                      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Изображение с градиентом
                      Hero(
                        tag: 'recipe_image_${widget.recipe.id}',
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: widget.recipe.image == null ||
                                    widget.recipe.image!.isEmpty
                                ? Container(
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
                                    child: Icon(
                                      Icons.restaurant_menu,
                                      size: 40,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  )
                                : Image.network(
                                    getOptimizedImageUrl(widget.recipe.image!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
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
                                      child: Icon(
                                        Icons.image_not_supported,
                                        color: theme.colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Кнопка избранного с анимацией
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: widget.favoritesLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : IconButton(
                                          key: ValueKey(widget.isFavorite),
                                          icon: Icon(
                                            widget.isFavorite
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: widget.isFavorite
                                                ? Colors.red
                                                : theme.colorScheme.onSurfaceVariant,
                                          ),
                                          iconSize: 24,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: widget.onFavoriteTap,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Метаданные
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (widget.recipe.calories != null)
                                  _InfoChip(
                                    icon: Icons.local_fire_department,
                                    label: '${widget.recipe.calories} ккал',
                                    color: Colors.orange,
                                  ),
                                if (_getProtein() != null)
                                  _InfoChip(
                                    icon: Icons.fitness_center,
                                    label: '${_getProtein()!.toStringAsFixed(1)} г белков',
                                    color: Colors.blue,
                                  ),
                                if (_getFat() != null)
                                  _InfoChip(
                                    icon: Icons.opacity,
                                    label: '${_getFat()!.toStringAsFixed(1)} г жиров',
                                    color: Colors.yellow.shade700,
                                  ),
                                if (_getCarbs() != null)
                                  _InfoChip(
                                    icon: Icons.eco,
                                    label: '${_getCarbs()!.toStringAsFixed(1)} г углеводов',
                                    color: Colors.green,
                                  ),
                                _InfoChip(
                                  icon: Icons.restaurant,
                                  label: '${ingredients.length} ингр.',
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double? _getProtein() {
    final nutrition = widget.recipe.nutrition;
    if (nutrition == null) return null;
    final protein = nutrition['protein'] ?? nutrition['proteins'];
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
    if (nutrition == null) return null;
    final carbs = nutrition['carbs'] ?? nutrition['carbohydrates'] ?? nutrition['carb'];
    if (carbs == null) return null;
    if (carbs is num) return carbs.toDouble();
    if (carbs is String) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(carbs);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

