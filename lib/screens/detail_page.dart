// lib/screens/detail_page.dart
import 'dart:convert';
import '../utils/api_error_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/recipe_network_image.dart';
import '../models/recipe.dart';
import '../models/recipe_model.dart';
import '../features/meal_plan/presentation/add_to_meal_plan_screen.dart';
import '../services/recipe_comments_service.dart';
import '../services/comment_service.dart';
import '../services/recipe_interaction_stats.dart';
import '../services/author_subscription_service.dart';
import '../services/auth_service.dart';
import '../services/saved_posts_service.dart';
import '../services/shopping_service.dart';
import '../widgets/share_action_sheet.dart';
import '../widgets/fullscreen_image_viewer.dart';
import 'cooking_mode_screen.dart';
import '../services/recipe_notes_service.dart';
import '../utils/recipe_nutrition.dart';
import '../core/layout/floating_bottom_padding.dart';
import '../features/settings/application/subscription_status_provider.dart';
import '../features/subscription/presentation/widgets/nutrition_upsell.dart';

class DetailPage extends StatefulWidget {
  final Recipe recipe;
  final bool isFavorite;
  final VoidCallback onToggle;

  const DetailPage({
    super.key,
    required this.recipe,
    required this.isFavorite,
    required this.onToggle,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late bool fav;
  bool _isSaved = false;
  bool _isSavedLoading = false;
  bool _isSubscribed = false;
  bool _subscriptionLoading = false;
  List<RecipeComment> _comments = [];
  bool _commentsLoading = false;
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();

  /// Резерв под закреплённый композер комментариев, чтобы последние комментарии не прятались под панелью.
  static const double _kCommentComposerScrollReserve = 200;
  int _selectedServings = 1;
  String _recipeNote = '';
  final _noteController = TextEditingController();
  int? _replyToCommentId;
  String? _replyToAuthor;
  double _avgRating = 0;
  int _ratingCount = 0;
  final Set<int> _expandedReplyThreads = <int>{};
  bool _statsDirty = false;

  String get _recipeStatsSource => widget.recipe.source ?? 'spoonacular';

  void _markStatsDirty() => _statsDirty = true;

  void _popWithResult() {
    if (_statsDirty) {
      Navigator.of(context).pop(
        RecipeDetailPopResult(
          recipeId: widget.recipe.id,
          source: _recipeStatsSource,
          commentCount: _comments.length,
          avgRating: _avgRating,
          ratingCount: _ratingCount,
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _focusCommentInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commentFocusNode.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    fav = widget.isFavorite;
    _selectedServings = widget.recipe.servings ?? 1;
    if (_selectedServings < 1) _selectedServings = 1;
    _loadNote();
    _loadComments();
    _loadRecipeRating();
    _loadSavedStatus();
    if (widget.recipe.author != null && widget.recipe.author!.isNotEmpty) {
      _checkSubscription();
    }
  }

  bool get _canSaveRecipe {
    // Теперь можно сохранять все рецепты: пользователей, каналов и Spoonacular
    return true;
  }

  bool get _isSpoonacularRecipe {
    final source = widget.recipe.source?.trim().toLowerCase();
    if (source == 'user' || source == 'channel') return false;
    if (source == 'spoonacular') return true;

    // Надежный fallback: по домену изображений Spoonacular.
    final mediaCandidates = <String?>[
      widget.recipe.image,
      widget.recipe.sourceImage,
      widget.recipe.videoThumbnail,
    ];
    final hasSpoonacularMedia = mediaCandidates.any((url) {
      final u = url?.trim().toLowerCase();
      if (u == null || u.isEmpty) return false;
      return u.contains('img.spoonacular.com') || u.contains('spoonacular.com');
    });
    if (hasSpoonacularMedia) return true;

    // Spoonacular IDs обычно шестизначные/семизначные; у локальных постов обычно маленькие.
    if (widget.recipe.id >= 100000) return true;

    // Последний fallback: если автора нет — считаем внешним (Spoonacular) рецептом.
    final hasAuthor = (widget.recipe.author ?? '').trim().isNotEmpty;
    return !hasAuthor;
  }

  Future<void> _loadSavedStatus() async {
    setState(() => _isSavedLoading = true);
    try {
      if (_isSpoonacularRecipe) {
        final saved = await SavedPostsService.isRecipeSaved(widget.recipe.id);
        if (mounted) {
          setState(() => _isSaved = saved);
        }
      } else {
        final saved = await SavedPostsService.isPostSaved(widget.recipe.id);
        if (mounted) {
          setState(() => _isSaved = saved);
        }
      }
    } catch (_) {
      // Игнорируем ошибки загрузки статуса сохранения
    } finally {
      if (mounted) setState(() => _isSavedLoading = false);
    }
  }

  Future<void> _loadNote() async {
    final note = await RecipeNotesService.getNote(widget.recipe.id);
    if (mounted) {
      _recipeNote = note ?? '';
      _noteController.text = _recipeNote;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    try {
      debugPrint(
        '🧵 Load comments for recipe=${widget.recipe.id}, source=${widget.recipe.source}, spoonacular=$_isSpoonacularRecipe',
      );
      if (_isSpoonacularRecipe) {
        final comments =
            await RecipeCommentsService.getComments(widget.recipe.id.toString());
        setState(() {
          _comments = comments;
          _commentsLoading = false;
        });
        return;
      }

      final response = await CommentService.getComments(
        widget.recipe.id,
        limit: 100,
        offset: 0,
      );
      final mapped = response.comments
          .map(
            (c) => RecipeComment(
              id: c.id,
              recipeId: c.postId.toString(),
              author: c.authorName ?? 'Неизвестный',
              authorAvatar: c.authorAvatar,
              authorId: c.userId.toString(),
              text: c.text,
              parentId: c.parentId,
              rating: c.rating,
              createdAt: c.createdAt.millisecondsSinceEpoch ~/ 1000,
            ),
          )
          .toList();
      setState(() {
        _comments = mapped;
        _commentsLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _commentsLoading = false);
      }
    }
  }

  Future<void> _loadRecipeRating() async {
    try {
      final data = _isSpoonacularRecipe
          ? await RecipeCommentsService.getRecipeRating(widget.recipe.id.toString())
          : await CommentService.getPostRating(widget.recipe.id);
      if (!mounted) return;
      setState(() {
        _avgRating = (data['rating'] as num?)?.toDouble() ?? 0;
        _ratingCount = (data['count'] as int?) ?? 0;
      });
    } catch (_) {
      // ignore rating loading errors
    }
  }

  Future<void> _checkSubscription() async {
    if (widget.recipe.author == null) return;
    // Используем временный идентификатор пользователя (в реальном приложении из AuthService)
    final subscriber = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final isSub = await AuthorSubscriptionService.isSubscribed(
      subscriber,
      widget.recipe.author!,
    );
    setState(() => _isSubscribed = isSub);
  }

  Future<void> _toggleSubscription() async {
    if (widget.recipe.author == null) return;
    setState(() => _subscriptionLoading = true);
    final subscriber = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final success = _isSubscribed
        ? await AuthorSubscriptionService.unsubscribe(subscriber, widget.recipe.author!)
        : await AuthorSubscriptionService.subscribe(subscriber, widget.recipe.author!);
    if (success) {
      setState(() {
        _isSubscribed = !_isSubscribed;
        _subscriptionLoading = false;
      });
    } else {
      setState(() => _subscriptionLoading = false);
    }
  }

  int? _selectedRating;
  static const _menuCook = 'cook';
  static const _menuPlan = 'plan';
  static const _menuShopping = 'shopping';
  static const _menuSave = 'save';

  Future<void> _handleMenuAction(String value, Recipe r) async {
    switch (value) {
      case _menuCook:
        if (r.steps.isNotEmpty || (r.translatedSteps?.isNotEmpty == true)) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CookingModeScreen(recipe: r),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет пошаговой инструкции')),
          );
        }
        break;
      case _menuPlan:
        await _addToMealPlan();
        break;
      case _menuShopping:
        await _addToShoppingList();
        break;
      case _menuSave:
        await _toggleSaved();
        break;
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _selectedRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите комментарий или выберите оценку')),
      );
      return;
    }

    // Получаем данные текущего пользователя
    final currentUser = await AuthService.getCurrentUser();
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Необходимо войти в систему')),
      );
      return;
    }
    
    // Берем имя из профиля пользователя
    final author = currentUser.name.isNotEmpty ? currentUser.name : (currentUser.username ?? currentUser.email);
    final authorId = currentUser.id.toString();
    final authorAvatar = currentUser.avatarUrl;

    try {
      if (_isSpoonacularRecipe) {
        final selectedRating = _selectedRating;
        final comment = await RecipeCommentsService.addComment(
          widget.recipe.id.toString(),
          author,
          text,
          authorAvatar: authorAvatar,
          authorId: authorId,
          parentId: _replyToCommentId,
          rating: selectedRating,
        );

        if (comment != null) {
          if (mounted) {
            setState(() {
              _comments.removeWhere((c) => c.id == comment.id);
              _comments = [comment, ..._comments];
              _commentController.clear();
              _selectedRating = null;
              _replyToCommentId = null;
              _replyToAuthor = null;
            });
            _markStatsDirty();
          }
          if (selectedRating != null && selectedRating > 0) {
            await _loadRecipeRating();
            if (mounted) _markStatsDirty();
          }
          _showNotice('Комментарий добавлен');
        } else {
          _showNotice('Ошибка при добавлении комментария');
        }
        return;
      }

      final created = await CommentService.createComment(
        widget.recipe.id,
        text,
        parentId: _replyToCommentId,
        rating: _selectedRating,
      );
      final optimistic = RecipeComment(
        id: created.id,
        recipeId: created.postId.toString(),
        author: created.authorName ?? author,
        authorAvatar: created.authorAvatar ?? authorAvatar,
        authorId: created.userId.toString(),
        text: created.text,
        rating: created.rating,
        parentId: created.parentId,
        createdAt: created.createdAt.millisecondsSinceEpoch ~/ 1000,
      );
      if (mounted) {
        setState(() {
          _comments = [optimistic, ..._comments];
          _commentController.clear();
          _selectedRating = null;
          _replyToCommentId = null;
          _replyToAuthor = null;
        });
        _markStatsDirty();
      }
      _showNotice('Комментарий добавлен');
    } catch (e) {
      _showNotice(
        userVisibleError(e, fallback: 'Не удалось добавить комментарий'),
      );
    }
  }

  Future<void> _deleteComment(RecipeComment comment) async {
    final currentUser = await AuthService.getCurrentUser();
    final authorId = currentUser?.id.toString();

    if (comment.authorId != authorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы можете удалить только свои комментарии')),
      );
      return;
    }

    bool success;
    if (_isSpoonacularRecipe) {
      success = await RecipeCommentsService.deleteComment(
        widget.recipe.id.toString(),
        comment.id,
        authorId: authorId,
      );
    } else {
      try {
        await CommentService.deleteComment(comment.id);
        success = true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                userVisibleError(e, fallback: 'Не удалось удалить комментарий'),
              ),
            ),
          );
        }
        return;
      }
    }

    if (success) {
      await _loadComments();
      _markStatsDirty();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Комментарий удален')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить комментарий')),
      );
    }
  }

  Future<void> _toggle() async {
    try {
      await Future.microtask(() => widget.onToggle());
      if (mounted) {
        setState(() => fav = !fav);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось добавить в избранное'))),
        );
      }
    }
  }

  Future<void> _toggleSaved() async {
    setState(() => _isSavedLoading = true);
    try {
      if (_isSpoonacularRecipe) {
        // Сохраняем рецепт Spoonacular
        if (_isSaved) {
          await SavedPostsService.unsaveRecipe(widget.recipe.id);
        } else {
          await SavedPostsService.saveRecipe(widget.recipe);
        }
      } else {
        // Сохраняем пост пользователя/канала
        if (_isSaved) {
          await SavedPostsService.unsavePostById(widget.recipe.id);
        } else {
          await SavedPostsService.savePostById(widget.recipe.id);
        }
      }
      if (mounted) {
        setState(() => _isSaved = !_isSaved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavedLoading = false);
    }
  }
  
  double? _getProtein(Recipe recipe) {
    final nutrition = recipe.nutrition;
    if (nutrition == null) return null;
    
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

  double? _getFat(Recipe recipe) => parseNutritionFat(recipe.nutrition);

  double? _getCarbs(Recipe recipe) {
    final nutrition = recipe.nutrition;
    if (nutrition == null) return null;
    
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

  Widget _nutritionChip(
    BuildContext context, {
    required bool canViewNutrition,
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    final locked = !canViewNutrition;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: tint),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (locked) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.lock_outline,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
      backgroundColor: tint.withValues(alpha: 0.1),
      onPressed: locked
          ? () => showNutritionUpsellSheet(context)
          : null,
    );
  }

  Future<void> _addToMealPlan() async {
    try {
      final recipeModel = _convertToRecipeModel(widget.recipe);
      await Navigator.of(context).push<DateTime>(
        MaterialPageRoute(
          builder: (_) => AddToMealPlanScreen(recipe: recipeModel),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось открыть план питания'))),
        );
      }
    }
  }

  Future<void> _addToShoppingList() async {
    final r = widget.recipe;
    final list = r.translatedIngredients?.isNotEmpty == true
        ? r.translatedIngredients!
        : r.ingredients;
    if (list.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У рецепта нет списка ингредиентов')),
        );
      }
      return;
    }
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AddToShoppingSheet(ingredients: list),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await ShoppingService.instance.addItemsFromRecipe(selected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено в список покупок: ${selected.length}')),
      );
    }
  }

  /// Поделиться рецептом: только название и ссылка на открытие в приложении (без полного текста).
  void _shareRecipe() {
    ShareActionSheet.showForRecipe(context, recipe: widget.recipe);
  }

  /// Масштабирует количество в строке ингредиента (например "200 г муки" -> при factor 2 "400 г муки").
  String _scaleIngredient(String s, double factor) {
    if (factor == 1.0) return s;
    final match = RegExp(r'^(\d+(?:[.,]\d+)?)').firstMatch(s);
    if (match == null) return s;
    final numStr = match.group(1)!.replaceAll(',', '.');
    final value = double.tryParse(numStr);
    if (value == null) return s;
    final scaled = value * factor;
    final replacement = scaled >= 1 && scaled == scaled.roundToDouble()
        ? scaled.toInt().toString()
        : scaled.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return s.replaceFirst(match.group(1)!, replacement);
  }

  RecipeModel _convertToRecipeModel(Recipe recipe) {
    final stepsRaw = recipe.translatedSteps?.isNotEmpty == true
        ? recipe.translatedSteps!
        : recipe.steps;
    final stepsList = stepsRaw
        .map((s) => (s['step'] ?? s['text'] ?? s['instruction'] ?? '').toString())
        .toList();
    final ingredientsList = recipe.translatedIngredients?.isNotEmpty == true
        ? recipe.translatedIngredients!
        : recipe.ingredients;
    return RecipeModel(
      id: recipe.id.toString(),
      title: recipe.translatedTitle ?? recipe.title,
      cookTime: 0,
      ingredients: ingredientsList,
      steps: stepsList,
      image: recipe.image,
      updatedAt: DateTime.now(),
      calories: recipe.calories?.toDouble(),
      proteinG: recipe.nutrientGrams('Protein'),
      carbsG: recipe.nutrientGrams('Carbohydrates'),
      fatG: recipe.nutrientGrams('Fat'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    // Всегда используем перевод если он есть (из настроек)
    final ingredientsRaw = r.translatedIngredients?.isNotEmpty == true
        ? r.translatedIngredients!
        : r.ingredients;
    final baseServings = r.servings ?? 1;
    final factor = baseServings > 0 ? _selectedServings / baseServings : 1.0;
    final ingredients = factor == 1.0
        ? ingredientsRaw
        : ingredientsRaw.map((s) => _scaleIngredient(s, factor)).toList();
    final steps = r.translatedSteps?.isNotEmpty == true
        ? r.translatedSteps!
        : r.steps;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithResult();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _buildCommentComposerBar(context),
      body: CustomScrollView(
        slivers: [
          // Hero изображение или видео
          SliverAppBar(
            expandedHeight: (r.videoThumbnail != null && r.videoThumbnail!.isNotEmpty) || 
                           (r.image != null && r.image!.isNotEmpty) ? 300 : 150,
            pinned: true,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _popWithResult,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  tooltip: 'Поделиться рецептом',
                  onPressed: () => _shareRecipe(),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    fav ? Icons.favorite : Icons.favorite_border,
                    color: fav ? Colors.red : Colors.white,
                  ),
                  tooltip: fav ? 'Удалить из избранного' : 'Добавить в избранное',
                  onPressed: _toggle,
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Colors.white),
                  tooltip: 'Действия',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 10,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  onSelected: (value) => _handleMenuAction(value, r),
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: _menuCook,
                      child: Row(
                        children: [
                          Icon(Icons.menu_book, size: 20),
                          SizedBox(width: 10),
                          Text('Режим готовки'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: _menuPlan,
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 20),
                          SizedBox(width: 10),
                          Text('В план питания'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: _menuShopping,
                      child: Row(
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('В список покупок'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: _menuSave,
                      child: Row(
                        children: [
                          Icon(
                            _isSaved ? Icons.bookmark : Icons.bookmark_border,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(_isSaved ? 'Убрать из сохраненных' : 'Сохранить'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            flexibleSpace: Hero(
              tag: 'recipe_image_${r.id}',
              child: FlexibleSpaceBar(
                background: _buildHeroImage(context, r),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      r.translatedTitle?.isNotEmpty == true ? r.translatedTitle! : r.title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (r.translatedTitle != null && r.translatedTitle != r.title) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Оригинальное название: ${r.title}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.favorite, color: Colors.red, size: 18),
                          label: Text('${r.likesCount ?? 0}'),
                        ),
                        Chip(
                          avatar: const Icon(Icons.comment_outlined, size: 18),
                          label: Text('${_comments.length}'),
                        ),
                        Chip(
                          avatar: const Icon(Icons.star, color: Colors.amber, size: 18),
                          label: Text(
                            _ratingCount > 0
                                ? '${_avgRating.toStringAsFixed(1)} ($_ratingCount)'
                                : '0.0 (0)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Метаданные (калории и БЖУ)
                  if (r.calories != null ||
                      _getProtein(r) != null ||
                      _getFat(r) != null ||
                      _getCarbs(r) != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final canViewNutrition =
                            ref.watch(canViewRecipeNutritionProvider);
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(opacity: value, child: child);
                          },
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (r.calories != null)
                                _nutritionChip(
                                  context,
                                  canViewNutrition: canViewNutrition,
                                  icon: Icons.local_fire_department_outlined,
                                  label: canViewNutrition
                                      ? '${r.calories} ккал'
                                      : 'Калории',
                                  tint: Colors.orange,
                                ),
                              if (_getProtein(r) != null)
                                _nutritionChip(
                                  context,
                                  canViewNutrition: canViewNutrition,
                                  icon: Icons.fitness_center,
                                  label: canViewNutrition
                                      ? '${_getProtein(r)!.toStringAsFixed(1)} г белков'
                                      : 'Белки',
                                  tint: Colors.blue,
                                ),
                              if (_getFat(r) != null)
                                _nutritionChip(
                                  context,
                                  canViewNutrition: canViewNutrition,
                                  icon: Icons.opacity,
                                  label: canViewNutrition
                                      ? '${_getFat(r)!.toStringAsFixed(1)} г жиров'
                                      : 'Жиры',
                                  tint: Colors.yellow.shade700,
                                ),
                              if (_getCarbs(r) != null)
                                _nutritionChip(
                                  context,
                                  canViewNutrition: canViewNutrition,
                                  icon: Icons.eco,
                                  label: canViewNutrition
                                      ? '${_getCarbs(r)!.toStringAsFixed(1)} г углеводов'
                                      : 'Углеводы',
                                  tint: Colors.green,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  // Видео, если есть
                  if (r.videoUrl != null && r.videoUrl!.isNotEmpty) ...[
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(opacity: value, child: child);
                      },
                      child: _buildVideoSection(context, r),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Автор, если это рецепт пользователя
                  if (r.author != null && r.author!.isNotEmpty) ...[
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(opacity: value, child: child);
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Автор: ${r.author}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Описание
                  if (r.summary != null && r.summary!.isNotEmpty) ...[
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(opacity: value, child: child);
                      },
                      child: Text(
                        r.summary!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Мои заметки к рецепту
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 620),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Мои заметки',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Например: меньше соли, заменить X на Y...',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          onChanged: (value) {
                            _recipeNote = value;
                            RecipeNotesService.setNote(widget.recipe.id, value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Ингредиенты
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ингредиенты',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (ingredients.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [1, 2, 4, 6, 8].map((n) {
                              final selected = _selectedServings == n;
                              return ChoiceChip(
                                label: Text('$n порц.'),
                                selected: selected,
                                onSelected: (v) {
                                  if (v) setState(() => _selectedServings = n);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (ingredients.isNotEmpty)
                          ...ingredients.asMap().entries.map((entry) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 800 + (entry.key * 50)),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(20 * (1 - value), 0),
                                    child: child,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        entry.value,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                        else
                          Text(
                            'Нет данных об ингредиентах.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Шаги приготовления
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Шаги приготовления',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (steps.isNotEmpty)
                          ...steps.asMap().entries.map((entry) {
                            final step = entry.value;
                            final num = step['number'] ?? entry.key + 1;
                            // Преобразуем txt в строку, если это не строка
                            // Проверяем все возможные поля для текста шага
                            final txtRaw = step['step'] ?? 
                                          step['text'] ?? 
                                          step['instruction'] ?? 
                                          (step.toString());
                            // Убираем лишние символы JSON, если это строка-представление Map
                            String txt = txtRaw is String ? txtRaw : txtRaw.toString();
                            // Если это JSON-строка объекта, пытаемся извлечь текст
                            if (txt.startsWith('{') && txt.contains('step')) {
                              try {
                                final decoded = jsonDecode(txt) as Map<String, dynamic>;
                                txt = decoded['step']?.toString() ?? 
                                      decoded['text']?.toString() ?? 
                                      decoded['instruction']?.toString() ?? 
                                      txt;
                              } catch (e) {
                                // Если не удалось распарсить, оставляем как есть
                              }
                            }
                            // Извлекаем изображение шага
                            dynamic imgRaw = step['image'] ?? step['image_url'];
                            String? imgUrl;
                            if (imgRaw != null) {
                              if (imgRaw is String) {
                                imgUrl = imgRaw.isNotEmpty && imgRaw != 'null' && imgRaw.trim().isNotEmpty ? imgRaw.trim() : null;
                              } else {
                                final imgStr = imgRaw.toString();
                                imgUrl = imgStr.isNotEmpty && imgStr != 'null' && imgStr.trim().isNotEmpty ? imgStr.trim() : null;
                              }
                            }
                            // Логирование для отладки
                            debugPrint('🔍 Шаг $num: step=$step, imgRaw=$imgRaw, imgUrl=$imgUrl');
                            if (imgUrl != null && imgUrl.isNotEmpty) {
                              debugPrint('🖼️ Шаг $num: найдено изображение $imgUrl');
                            } else {
                              debugPrint('⚠️ Шаг $num: изображение отсутствует. imgRaw=$imgRaw, step keys=${step.keys.toList()}');
                            }
                            
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 900 + (entry.key * 100)),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$num',
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onPrimary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              txt,
                                              style: Theme.of(context).textTheme.bodyLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (imgUrl != null && imgUrl.isNotEmpty && imgUrl != 'null') ...[
                                        const SizedBox(height: 12),
                                        GestureDetector(
                                          onTap: () {
                                            // Собираем все изображения шагов для полноэкранного просмотра
                                            final allStepImages = <String>[];
                                            for (var s in steps) {
                                              final stepImg = s['image'] ?? s['image_url'];
                                              if (stepImg != null && stepImg.toString().isNotEmpty && stepImg.toString() != 'null') {
                                                allStepImages.add(stepImg.toString());
                                              }
                                            }
                                            if (allStepImages.isNotEmpty && imgUrl != null) {
                                              final currentIndex = allStepImages.indexOf(imgUrl);
                                              showFullscreenImageViewer(
                                                context,
                                                imageUrls: allStepImages,
                                                initialIndex: currentIndex >= 0 ? currentIndex : 0,
                                              );
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: RecipeNetworkImage(
                                              rawUrl: imgUrl,
                                              profile: RecipeImageProfile.card,
                                              height: 180,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          })
                        else
                          Text(
                            'Шаги приготовления пока не доступны.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Комментарии
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: child);
                    },
                    child: _buildCommentsSection(context),
                  ),
                  SizedBox(
                    height: 12 +
                        floatingBottomPadding(context) +
                        _kCommentComposerScrollReserve,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCommentComposerBar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyToCommentId != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ответ для: ${_replyToAuthor ?? 'пользователя'}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _replyToCommentId = null;
                            _replyToAuthor = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              FutureBuilder(
                future: AuthService.getCurrentUser(),
                builder: (context, snapshot) {
                  final currentUser = snapshot.data;
                  if (currentUser == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'От имени: ${currentUser.name}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _replyToCommentId != null
                            ? 'Ваш ответ…'
                            : 'Комментарий…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _addComment,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: [
                  Text(_isSpoonacularRecipe ? 'Оценка рецепта: ' : 'Оценка: '),
                  ...List.generate(5, (index) {
                    return IconButton(
                      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      icon: Icon(
                        _selectedRating != null && index < _selectedRating!
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () {
                        setState(() => _selectedRating = index + 1);
                      },
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    final commentIds = _comments.map((c) => c.id).toSet();
    final topLevelComments = _comments
        .where((c) => c.parentId == null || !commentIds.contains(c.parentId))
        .toList();
    final commentsById = <int, RecipeComment>{
      for (final c in _comments) c.id: c,
    };
    final repliesByParent = <int, List<RecipeComment>>{};
    for (final comment in _comments) {
      final parentId = comment.parentId;
      if (parentId != null) {
        repliesByParent.putIfAbsent(parentId, () => <RecipeComment>[]).add(comment);
      }
    }
    topLevelComments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final list in repliesByParent.values) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    int rootIdFor(RecipeComment c) {
      RecipeComment current = c;
      final visited = <int>{};
      while (current.parentId != null &&
          commentsById.containsKey(current.parentId) &&
          !visited.contains(current.id)) {
        visited.add(current.id);
        current = commentsById[current.parentId]!;
      }
      return current.id;
    }

    final repliesByRoot = <int, List<RecipeComment>>{};
    for (final c in _comments) {
      if (c.parentId == null) continue;
      final rootId = rootIdFor(c);
      repliesByRoot.putIfAbsent(rootId, () => <RecipeComment>[]).add(c);
    }
    for (final list in repliesByRoot.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Комментарии (${_comments.length})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (widget.recipe.author != null && widget.recipe.author!.isNotEmpty)
              TextButton.icon(
                onPressed: _subscriptionLoading ? null : _toggleSubscription,
                icon: _subscriptionLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isSubscribed ? Icons.check_circle : Icons.person_add,
                        size: 18,
                      ),
                label: Text(_isSubscribed ? 'Подписан' : 'Подписаться'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_ratingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: Colors.amber.shade600, size: 20),
                const SizedBox(width: 6),
                Text(
                  '${_avgRating.toStringAsFixed(1)} из 5',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  '($_ratingCount оценок)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        if (_commentsLoading)
          const Center(child: CircularProgressIndicator())
        else if (_comments.isEmpty)
          Text(
            'Пока нет комментариев. Будьте первым!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          )
        else
          ...topLevelComments.map((comment) {
            final replies = repliesByRoot[comment.id] ?? const <RecipeComment>[];
            final isExpanded = _expandedReplyThreads.contains(comment.id);
            return FutureBuilder(
              future: AuthService.getCurrentUser(),
              builder: (context, snapshot) {
                final currentUser = snapshot.data;
                final currentUserId = currentUser?.id.toString();

                Widget buildCommentTile(RecipeComment c, {double leftPad = 0}) {
                  final canDelete = c.authorId != null &&
                      currentUserId != null &&
                      currentUserId == c.authorId;

                  return Padding(
                    padding: EdgeInsets.only(left: leftPad, bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            c.authorAvatar != null && c.authorAvatar!.isNotEmpty
                                ? CircleAvatar(
                                    radius: 16,
                                    backgroundImage: NetworkImage(c.authorAvatar!),
                                    onBackgroundImageError: (_, __) {},
                                  )
                                : CircleAvatar(
                                    radius: 16,
                                    child: Text(c.author[0].toUpperCase()),
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.author,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (c.rating != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(5, (index) {
                                            return Icon(
                                              index < c.rating! ? Icons.star : Icons.star_border,
                                              size: 14,
                                              color: Colors.amber,
                                            );
                                          }),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(c.text),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _replyToCommentId = c.id;
                                            _replyToAuthor = c.author;
                                          });
                                          _focusCommentInput();
                                        },
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          visualDensity: const VisualDensity(
                                            horizontal: -2,
                                            vertical: -3,
                                          ),
                                          minimumSize: const Size(0, 20),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('Ответить'),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatDate(c.createdAt),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (canDelete) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          visualDensity: const VisualDensity(
                                            horizontal: -4,
                                            vertical: -4,
                                          ),
                                          constraints: const BoxConstraints.tightFor(
                                            width: 24,
                                            height: 24,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                          onPressed: () => _deleteComment(c),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    buildCommentTile(comment),
                    if (replies.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 6),
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedReplyThreads.remove(comment.id);
                                } else {
                                  _expandedReplyThreads.add(comment.id);
                                }
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 20),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              isExpanded
                                  ? 'Скрыть ответы'
                                  : 'Показать ответы (${replies.length})',
                            ),
                          ),
                        ),
                      ),
                    if (replies.isNotEmpty && isExpanded)
                      ...replies.map((reply) {
                        final parentAuthor = reply.parentId != null
                            ? commentsById[reply.parentId!]?.author
                            : null;
                        final mention = (parentAuthor != null && parentAuthor.isNotEmpty)
                            ? '$parentAuthor, '
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(left: 18),
                          child: buildCommentTile(
                            RecipeComment(
                              id: reply.id,
                              recipeId: reply.recipeId,
                              author: reply.author,
                              authorAvatar: reply.authorAvatar,
                              authorId: reply.authorId,
                              text: '$mention${reply.text}',
                              parentId: reply.parentId,
                              rating: reply.rating,
                              createdAt: reply.createdAt,
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            );
          }),
      ],
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 7) {
      return '${date.day}.${date.month}.${date.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} дн. назад';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} ч. назад';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} мин. назад';
    } else {
      return 'Только что';
    }
  }

  Widget _buildHeroImage(BuildContext context, Recipe r) {
    // Приоритет: videoThumbnail > image
    final primary = r.videoThumbnail ?? r.image;
    final fallback = r.sourceImage;
    
    if ((primary != null && primary.isNotEmpty) || (fallback != null && fallback.isNotEmpty)) {
      final primaryRaw =
          (primary != null && primary.isNotEmpty) ? primary : fallback!;
      return GestureDetector(
        onTap: () {
          final urls = <String>[
            primaryRaw,
            if (fallback != null &&
                fallback.isNotEmpty &&
                fallback != primaryRaw)
              fallback,
          ];
          showFullscreenImageViewer(
            context,
            imageUrls: urls,
            initialIndex: 0,
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            RecipeNetworkImage(
              rawUrl: primaryRaw,
              profile: RecipeImageProfile.detailHero,
              fit: BoxFit.cover,
              cacheKey: 'hero:${r.id}',
              errorWidget: _buildPlaceholder(context),
            ),
            // Иконка видео поверх изображения
            if (r.videoUrl != null && r.videoUrl!.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_circle_filled,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
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
      child: const Icon(Icons.restaurant_menu, size: 80),
    );
  }

  Widget _buildVideoSection(BuildContext context, Recipe r) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _playVideo(context, r.videoUrl!),
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Превью видео
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: r.videoThumbnail != null && r.videoThumbnail!.isNotEmpty
                    ? RecipeNetworkImage(
                        rawUrl: r.videoThumbnail!,
                        profile: RecipeImageProfile.detailHero,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.video_library, size: 48),
                        ),
                      )
                    : Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.video_library, size: 48),
                      ),
              ),
            ),
            // Кнопка воспроизведения
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
            // Метка "Видео"
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_filled, color: Colors.white, size: 16),
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
          ],
        ),
      ),
    );
  }

  void _playVideo(BuildContext context, String videoUrl) {
    // Открываем видео в диалоге или навигации
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Здесь можно использовать video_player пакет для воспроизведения
                  // Пока показываем ссылку
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Видео: $videoUrl',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Можно открыть в браузере или использовать video_player
                      Navigator.of(context).pop();
                    },
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижний лист выбора ингредиентов для добавления в список покупок.
class _AddToShoppingSheet extends StatefulWidget {
  final List<String> ingredients;

  const _AddToShoppingSheet({required this.ingredients});

  @override
  State<_AddToShoppingSheet> createState() => _AddToShoppingSheetState();
}

class _AddToShoppingSheetState extends State<_AddToShoppingSheet> {
  late List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.ingredients.length, true);
  }

  void _selectAll(bool value) {
    setState(() => _selected = List.filled(widget.ingredients.length, value));
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.where((e) => e).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Добавить в список покупок',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _selectAll(true),
                    child: const Text('Выбрать все'),
                  ),
                  TextButton(
                    onPressed: () => _selectAll(false),
                    child: const Text('Снять все'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.ingredients.length,
                itemBuilder: (context, i) {
                  return CheckboxListTile(
                    value: _selected[i],
                    onChanged: (v) {
                      setState(() => _selected[i] = v ?? true);
                    },
                    title: Text(widget.ingredients[i]),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: count == 0
                    ? null
                    : () {
                        final list = <String>[];
                        for (var i = 0; i < widget.ingredients.length; i++) {
                          if (_selected[i]) list.add(widget.ingredients[i]);
                        }
                        Navigator.of(context).pop(list);
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text('Добавить выбранные ($count)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
