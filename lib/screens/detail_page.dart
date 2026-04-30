// lib/screens/detail_page.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/recipe.dart';
import '../models/recipe_model.dart';
import '../features/meal_plan/presentation/add_to_meal_plan_screen.dart';
import '../services/recipe_comments_service.dart';
import '../services/author_subscription_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/saved_posts_service.dart';
import '../services/shopping_service.dart';
import '../widgets/fullscreen_image_viewer.dart';
import 'cooking_mode_screen.dart';
import '../services/recipe_notes_service.dart';

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
  int _selectedServings = 1;
  String _recipeNote = '';
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fav = widget.isFavorite;
    _selectedServings = widget.recipe.servings ?? 1;
    if (_selectedServings < 1) _selectedServings = 1;
    _loadNote();
    _loadComments();
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
    final source = widget.recipe.source;
    return source == null || source == 'spoonacular' || (source != 'user' && source != 'channel');
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
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    final comments = await RecipeCommentsService.getComments(widget.recipe.id.toString());
    setState(() {
      _comments = comments;
      _commentsLoading = false;
    });
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

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите комментарий')),
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
    final comment = await RecipeCommentsService.addComment(
      widget.recipe.id.toString(),
      author,
      text,
        authorAvatar: authorAvatar,
      authorId: authorId,
      rating: _selectedRating,
    );

    if (comment != null) {
      _commentController.clear();
      _selectedRating = null;
      _loadComments();
        if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Комментарий добавлен')),
      );
        }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при добавлении комментария')),
        );
      }
    }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при добавлении комментария: $e')),
        );
      }
    }
  }

  Future<void> _deleteComment(RecipeComment comment) async {
    final currentUser = await AuthService.getCurrentUser();
    final authorId = currentUser?.uid;

    if (comment.authorId != authorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы можете удалить только свои комментарии')),
      );
      return;
    }

    final success = await RecipeCommentsService.deleteComment(
      widget.recipe.id.toString(),
      comment.id,
      authorId: authorId,
    );

    if (success) {
      _loadComments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Комментарий удален')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при удалении комментария')),
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
          SnackBar(content: Text('Ошибка при добавлении в избранное: $e')),
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
          SnackBar(content: Text('Ошибка при сохранении: $e')),
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

  double? _getFat(Recipe recipe) {
    final nutrition = recipe.nutrition;
    if (nutrition == null) return null;
    
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

  Future<void> _addToMealPlan() async {
    try {
      final recipeModel = _convertToRecipeModel(widget.recipe);
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AddToMealPlanScreen(recipe: recipeModel),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть план питания: $e')),
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
    final r = widget.recipe;
    final title = r.translatedTitle ?? r.title;
    final link = 'haneat://recipe/${r.id}';
    final text = '$title\n\nОткрыть в приложении H.A.N. Eat: $link';
    Share.share(text, subject: title);
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
    return Scaffold(
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
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
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
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.menu_book, color: Colors.white),
                  tooltip: 'Режим готовки',
                  onPressed: () {
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
                  },
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.calendar_today, color: Colors.white),
                  tooltip: 'Добавить в план питания',
                  onPressed: () => _addToMealPlan(),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                  tooltip: 'Добавить ингредиенты в список покупок',
                  onPressed: () => _addToShoppingList(),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: _isSavedLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          _isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: Colors.white,
                        ),
                        tooltip: _isSaved ? 'Удалить из сохраненных' : 'Сохранить',
                        onPressed: _toggleSaved,
                      ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
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
                  // Метаданные (калории и БЖУ)
                  if (r.calories != null || _getProtein(r) != null || _getFat(r) != null || _getCarbs(r) != null)
                    TweenAnimationBuilder<double>(
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
                            Chip(
                              avatar: const Icon(Icons.local_fire_department_outlined),
                              label: Text('${r.calories} ккал'),
                              backgroundColor: Colors.orange.withOpacity(0.1),
                            ),
                          if (_getProtein(r) != null)
                            Chip(
                              avatar: const Icon(Icons.fitness_center),
                              label: Text('${_getProtein(r)!.toStringAsFixed(1)} г белков'),
                              backgroundColor: Colors.blue.withOpacity(0.1),
                            ),
                          if (_getFat(r) != null)
                            Chip(
                              avatar: const Icon(Icons.opacity),
                              label: Text('${_getFat(r)!.toStringAsFixed(1)} г жиров'),
                              backgroundColor: Colors.yellow.withOpacity(0.1),
                            ),
                          if (_getCarbs(r) != null)
                            Chip(
                              avatar: const Icon(Icons.eco),
                              label: Text('${_getCarbs(r)!.toStringAsFixed(1)} г углеводов'),
                              backgroundColor: Colors.green.withOpacity(0.1),
                            ),
                        ],
                      ),
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
                                          (step is Map ? step.toString() : step);
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
                              debugPrint('⚠️ Шаг $num: изображение отсутствует. imgRaw=$imgRaw, step keys=${step is Map ? step.keys.toList() : 'not a map'}');
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
                                                allStepImages.add(_getProxyUrl(stepImg.toString()));
                                              }
                                            }
                                            if (allStepImages.isNotEmpty && imgUrl != null) {
                                              final currentIndex = allStepImages.indexOf(_getProxyUrl(imgUrl!));
                                              showFullscreenImageViewer(
                                                context,
                                                imageUrls: allStepImages,
                                                initialIndex: currentIndex >= 0 ? currentIndex : 0,
                                              );
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              _getProxyUrl(imgUrl),
                                              height: 180,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return Container(
                                                  height: 180,
                                                  width: double.infinity,
                                                  color: Colors.grey[200],
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
                                              errorBuilder: (_, __, ___) => Container(
                                              height: 180,
                                              width: double.infinity,
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.error_outline, color: Colors.red),
                                            ),
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
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Комментарии',
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
        const SizedBox(height: 16),
        // Форма добавления комментария
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Показываем имя пользователя из профиля (только для информации)
                FutureBuilder(
                  future: AuthService.getCurrentUser(),
                  builder: (context, snapshot) {
                    final currentUser = snapshot.data;
                    if (currentUser != null) {
                      final userName = currentUser.name ?? currentUser.email ?? 'Пользователь';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              'От имени: $userName',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                // Выбор рейтинга
                Row(
                  children: [
                    const Text('Рейтинг: '),
                    ...List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          _selectedRating != null && index < _selectedRating!
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedRating = index + 1;
                          });
                        },
                      );
                    }),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _addComment,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Отправить'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Список комментариев
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
          ..._comments.map((comment) {
            return FutureBuilder(
              future: AuthService.getCurrentUser(),
              builder: (context, snapshot) {
                final currentUser = snapshot.data;
                final currentUserId = currentUser?.uid;
                final canDelete = comment.authorId != null && 
                                 currentUserId != null &&
                                 currentUserId == comment.authorId;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: comment.authorAvatar != null && comment.authorAvatar!.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(comment.authorAvatar!),
                            onBackgroundImageError: (_, __) {},
                          )
                        : CircleAvatar(
                            child: Text(comment.author[0].toUpperCase()),
                          ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            comment.author,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (comment.rating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (index) {
                              return Icon(
                                index < comment.rating! ? Icons.star : Icons.star_border,
                                size: 16,
                                color: Colors.amber,
                              );
                            }),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comment.text),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(comment.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: canDelete
                        ? IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteComment(comment),
                          )
                        : Text(
                            _formatDate(comment.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
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
    final imageUrl = r.videoThumbnail ?? r.image;
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final proxyUrl = _getProxyUrl(imageUrl);
      return GestureDetector(
        onTap: () {
          // Открываем изображение на полный экран
          showFullscreenImageViewer(
            context,
            imageUrls: [proxyUrl],
            initialIndex: 0,
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              proxyUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPlaceholder(context),
            ),
            // Иконка видео поверх изображения
            if (r.videoUrl != null && r.videoUrl!.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
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

  String _getProxyUrl(String originalUrl) {
    // Для Flutter Web используем прокси через бэкенд для обхода CORS
    // Для других платформ используем оригинальный URL
    if (originalUrl.startsWith('https://img.spoonacular.com') || 
        originalUrl.startsWith('https://spoonacular.com')) {
      // Используем прокси только для Spoonacular изображений
      final baseUrl = '${ApiService.baseUrl}/api/v1';
      final encodedUrl = Uri.encodeComponent(originalUrl);
      final proxyUrl = '$baseUrl/recipes/image-proxy?url=$encodedUrl';
      return proxyUrl;
    }
    // Для локальных URL (localhost) и URL из каналов просто возвращаем как есть
    // Они должны работать напрямую
    if (originalUrl.startsWith('http://localhost') || 
        originalUrl.startsWith('http://127.0.0.1') ||
        originalUrl.startsWith('/api/v1/uploads/')) {
      return originalUrl;
    }
    return originalUrl;
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
                    ? Image.network(
                        _getProxyUrl(r.videoThumbnail!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
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
                    color: Colors.black.withOpacity(0.6),
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
                  color: Colors.black.withOpacity(0.7),
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
                child: Text('Добавить выбранные ($count)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
