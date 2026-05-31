import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/analysis_mode.dart';
import '../../../models/recipe.dart';
import '../../../models/search_history_entry.dart';
import '../../../models/recipe_category.dart';
import '../../../screens/detail_page.dart';
import '../../../services/recipe_interaction_stats.dart';
import '../../../services/ai_scan_image.dart';
import '../../../services/ai_scan_gate.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../services/history_storage.dart';
import '../../../services/category_service.dart';
import '../../../widgets/modern_recipe_card.dart';
import '../../../widgets/recipe_network_image.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../settings/application/analysis_mode_controller.dart';
import '../application/menu_recommendations_refresh_provider.dart';
import '../../settings/application/analysis_mode_controller.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../../core/subscription/recipe_translation_access.dart';
import '../../../app/app_router.dart';
import '../../subscription/presentation/widgets/nutrition_upsell.dart';
import '../../../core/subscription/recipe_nutrition_access.dart';
import '../application/search_controller.dart';
import '../../../app/app_router.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../core/layout/floating_bottom_padding.dart';

/// Боковой зазор контента «Меню» от края экрана (единый для поиска, чипов и сетки).
const double _kMenuScreenEdgeGutter = 10.0;

/// Зазор между колонками карточек в сетке.
const double _kMenuGridCrossAxisSpacing = 10.0;

/// Оценка высоты блока под превью для сетки «Меню» ([ModernRecipeCard] с `compact: true`).
/// Завышение даёт «пустой» низ карточки; занижение — риск overflow на 2 строках заголовка.
const double _kMenuRecipeCardTextEstimate = 208;

double _menuGridCellWidth(double viewportWidth) {
  final edge = _kMenuScreenEdgeGutter * 2;
  return (viewportWidth - edge - _kMenuGridCrossAxisSpacing) / 2;
}

/// Соотношение сторон ячейки сетки (ширина / высота), чтобы высота совпадала с карточкой
/// и не оставалась серая полоса снизу при широком окне.
double _menuRecipeGridChildAspectRatio(
  double viewportWidth, {
  required double imageAspectRatio,
  double textBlockHeight = _kMenuRecipeCardTextEstimate,
}) {
  final w = _menuGridCellWidth(viewportWidth);
  if (w <= 0) return 0.5;
  final imageH = w / imageAspectRatio;
  final totalH = imageH + textBlockHeight;
  // Не ограничивать сверху жёстко: на широком окне формула даёт ratio > 0.82, иначе ячейка
  // выше контента — серая полоса снизу внутри [Card].
  return (w / totalH).clamp(0.35, 1.25);
}

/// Превью шире, чем квадрат (4:3) — ниже по высоте, меньше пустого поля под фото.
const double _kMenuCardImageAspect = 4 / 3;

double _menuRecipeTextBlockHeight(BuildContext context) {
  final factor =
      (MediaQuery.textScalerOf(context).scale(12) / 12.0).clamp(0.85, 1.2);
  return _kMenuRecipeCardTextEstimate * factor;
}

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late Future<RecommendationsResult> _recommendationsFuture;
  List<Recipe> _cachedRecommendations = []; // Кэш последних рекомендаций
  DateTime? _cacheTimestamp;
  static const _cacheDuration =
      Duration(minutes: 15); // Кэш на 15 минут для ускорения
  static const int _kMinRecommendationsToCache = 3;
  static List<Recipe> _sharedRecommendationsCache = [];
  static DateTime? _sharedCacheTimestamp;

  /// Последние флаги из GET /recommendations (для кэша карточек без повторного запроса).
  bool _lastSpoonacularQuotaExhausted = false;
  bool _lastSuggestPlusUpgrade = false;
  bool _lastViewerIsPlus = false;
  bool _recommendationsLoadFailed = false;
  List<int>? _imageWarmRecipeIds;

  void _warmImagesForRecipes(List<Recipe> recipes) {
    if (recipes.isEmpty) return;
    final ids = recipes.map((r) => r.id).toList();
    if (_imageWarmRecipeIds != null &&
        _imageWarmRecipeIds!.length == ids.length &&
        _listEqualsIds(_imageWarmRecipeIds!, ids)) {
      return;
    }
    _imageWarmRecipeIds = ids;
    final urls = recipes
        .map((r) => r.image ?? r.sourceImage ?? r.videoThumbnail ?? '')
        .where((u) => u.isNotEmpty)
        .take(6);
    unawaited(warmRecipeImageCache(urls));
  }

  static bool _listEqualsIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  RecommendationsResult _recommendationsFromCacheOnly() {
    return RecommendationsResult(
      recipes: _cachedRecommendations,
      spoonacularQuotaExhausted: _lastSpoonacularQuotaExhausted,
      suggestPlusUpgrade: _lastSuggestPlusUpgrade,
      viewerIsPlus: _lastViewerIsPlus,
    );
  }

  bool _shouldPersistRecommendationsCache(RecommendationsResult result) {
    return result.recipes.length >= _kMinRecommendationsToCache;
  }

  /// Увеличить при изменении состава полей в `/recommendations` (например author / author_avatar).
  static const int _kRecommendationsPayloadVersion = 11;
  static int _appliedRecommendationsPayloadVersion = 0;
  List<Recipe> _favorites = [];
  bool _favoritesLoading = false;
  bool _favoritesEnabled = true;
  String? _selectedTags;
  String? _selectedIngredients;
  int? _selectedMaxReadyTime; // Фильтр по времени готовки (мин)
  bool _hideMenuButtons = false;
  static const _scrollThreshold = 60.0;
  @override
  void initState() {
    super.initState();
    if (_appliedRecommendationsPayloadVersion <
        _kRecommendationsPayloadVersion) {
      _cachedRecommendations = [];
      _cacheTimestamp = null;
      _sharedRecommendationsCache = [];
      _sharedCacheTimestamp = null;
      _appliedRecommendationsPayloadVersion = _kRecommendationsPayloadVersion;
    }
    _controller.addListener(() {
      if (mounted) {
        setState(() {}); // Обновляем UI при изменении текста
        // Если поле поиска очищено, сбрасываем состояние поиска
        if (_controller.text.isEmpty) {
          ref.read(searchControllerProvider.notifier).reset();
        }
      }
    });
    // Предзагружаем рецепты сразу при инициализации
    final settings = ref.read(analysisSettingsProvider);

    // Поднимаем кэш из общего статического хранилища между открытиями экрана.
    if (_sharedRecommendationsCache.isNotEmpty &&
        _sharedCacheTimestamp != null) {
      _cachedRecommendations = List<Recipe>.from(_sharedRecommendationsCache);
      _cacheTimestamp = _sharedCacheTimestamp;
    }

  _recommendationsFuture = _fetchRecommendationsImmediate(settings);

    // Загружаем избранное параллельно (не блокируем UI)
    _loadFavorites();
    unawaited(ApiService.touchAiScanCreditsSilently());

  }

  Future<RecommendationsResult> _fetchRecommendationsImmediate(
      AnalysisSettingsState settings) async {
    // Загружаем теги асинхронно, чтобы не блокировать основной поток
    final tagsFuture = Future(() {
      try {
        return CategoryService.instance.getSpoonacularTagsForActiveCategories();
      } catch (e) {
        return <String>[];
      }
    });

    // Параллельно загружаем теги и делаем запрос
    final activeTags = await tagsFuture;
    final tagsString =
        activeTags.isNotEmpty ? activeTags.join(',') : (_selectedTags ?? '');

    try {
      final result = await ApiService.fetchRecommendations(
        limit: 8,
        tags: tagsString.isNotEmpty ? tagsString : null,
        ingredients: _selectedIngredients,
        mode: settings.mode,
        language: settings.language,
      );

      // Не кэшируем «бедный» ответ (1 карточка при исчерпании квоты Spoonacular)
      if (mounted && _shouldPersistRecommendationsCache(result)) {
        _cachedRecommendations = result.recipes;
        _cacheTimestamp = DateTime.now();
        _sharedRecommendationsCache = List<Recipe>.from(result.recipes);
        _sharedCacheTimestamp = _cacheTimestamp;
      }
      _lastSpoonacularQuotaExhausted = result.spoonacularQuotaExhausted;
      _lastSuggestPlusUpgrade = result.suggestPlusUpgrade;
      _lastViewerIsPlus = result.viewerIsPlus;
      if (mounted) {
        setState(() => _recommendationsLoadFailed = false);
      }

      if (result.recipes.isNotEmpty) {
        _warmImagesForRecipes(result.recipes);
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching recommendations: $e');
      }
      if (_cachedRecommendations.isNotEmpty) {
        if (mounted) {
          setState(() => _recommendationsLoadFailed = false);
        }
        return _recommendationsFromCacheOnly();
      }
      if (mounted) {
        setState(() => _recommendationsLoadFailed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(
                e,
                fallback: 'Не удалось загрузить рекомендации',
              ),
            ),
          ),
        );
      }
      return const RecommendationsResult(recipes: []);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    setState(() => _favoritesLoading = true);
    try {
      final favs = await ApiService.getFavorites().timeout(
        const Duration(seconds: 5),
        onTimeout: () => <Recipe>[], // Возвращаем пустой список при таймауте
      );
      if (!mounted) return;
      setState(() {
        _favorites = favs;
        _favoritesEnabled = true;
      });
    } catch (e) {
      if (!mounted) return;
      if (isAuthRelatedError(e)) {
        setState(() => _favoritesEnabled = false);
      }
    } finally {
      if (mounted) {
        setState(() => _favoritesLoading = false);
      }
    }
  }

  bool _isFavorite(int id) => _favorites.any((r) => r.id == id);

  Future<void> _toggleFavorite(Recipe recipe) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите, чтобы сохранять рецепты в избранное'),
        ),
      );
      await context.push(LoginRoute.path);
      if (mounted) {
        await _loadFavorites();
      }
      return;
    }

    // Проверяем, что у рецепта есть ID
    if (recipe.id == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить рецепт. Обновите страницу.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final wasFavorite = _isFavorite(recipe.id);
    // Оптимистично обновляем UI, чтобы лайк отображался сразу
    if (wasFavorite) {
      _favorites.removeWhere((r) => r.id == recipe.id);
    } else {
      _favorites.add(recipe);
    }
    if (mounted) setState(() {});

    try {
      if (wasFavorite) {
        await ApiService.removeFavorite(recipe.id);
      } else {
        // Убеждаемся, что рецепт имеет все необходимые поля перед отправкой
        final recipeJson = recipe.toJson();
        if (!recipeJson.containsKey('id') || recipeJson['id'] == null) {
          throw Exception('recipe has no id');
        }
        await ApiService.addFavorite(recipe);
      }
    } catch (e) {
      // Откатываем оптимистичное изменение при ошибке
      if (wasFavorite) {
        _favorites.add(recipe);
      } else {
        _favorites.removeWhere((r) => r.id == recipe.id);
      }
      if (!mounted) return;

      final errorMsg = e.toString().toLowerCase();
      String userMessage =
          userVisibleError(e, fallback: 'Не удалось добавить в избранное');

      // Обработка различных типов ошибок
      if (errorMsg.contains('recipe has no id') || errorMsg.contains('no id')) {
        userMessage =
            'Не удалось сохранить рецепт. Попробуйте обновить страницу.';
      } else if (errorMsg.contains('daily points limit') ||
          errorMsg.contains('points limit') ||
          errorMsg.contains('402')) {
        userMessage =
            'Лимит каталога рецептов на сегодня исчерпан. Повторите позже или оформите H.A.N. AI (от 199 ₽/мес).';
      } else if (errorMsg.contains('unauthorized') ||
          errorMsg.contains('401')) {
        userMessage =
            'Требуется вход в аккаунт или сессия истекла. Войдите снова и повторите.';
      } else if (errorMsg.contains('network') ||
          errorMsg.contains('connection')) {
        userMessage = 'Ошибка сети. Проверьте подключение к интернету.';
      } else if (errorMsg.contains('timeout')) {
        userMessage = 'Превышено время ожидания. Попробуйте позже.';
      }

      final isQuotaLike = errorMsg.contains('daily points') ||
          errorMsg.contains('points limit') ||
          errorMsg.contains('402');
      if (isQuotaLike) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Подписка',
              onPressed: () => context.push(SubscriptionRoute.path),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      setState(() {});
    }
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    List<String> activeTags = [];
    try {
      activeTags =
          CategoryService.instance.getSpoonacularTagsForActiveCategories();
    } catch (e) {
      // CategoryService not initialized, continue without tags
    }
    await ref.read(searchControllerProvider.notifier).search(
          query,
          tags: activeTags.isNotEmpty ? activeTags : null,
          maxReadyTime: _selectedMaxReadyTime,
        );
  }

  Future<void> _fetchRecommendations(AnalysisSettingsState settings) async {
    // Сбрасываем кэш при явном обновлении
    _cachedRecommendations = [];
    _cacheTimestamp = null;
    _sharedRecommendationsCache = [];
    _sharedCacheTimestamp = null;

    setState(() {
      _recommendationsLoadFailed = false;
      _recommendationsFuture = _fetchRecommendationsImmediate(settings);
    });
  }

  Future<void> _runSearchFromHistory(String query) async {
    _controller.text = query;
    await _runSearch();
  }

  void _applyQuickFilter(
    String label,
    String tag,
    AnalysisSettingsState settings, {
    required bool canViewNutrition,
  }) {
    if (RecipeNutritionAccess.isNutritionFilterTag(tag) && !canViewNutrition) {
      unawaited(showNutritionUpsellSheet(context));
      return;
    }
    _controller.text = label;
    final maxMin = label == 'Быстро' ? 15 : _selectedMaxReadyTime;
    ref
        .read(searchControllerProvider.notifier)
        .searchByTag(label, tag, maxReadyTime: maxMin);
  }

  Future<void> _openMediaPicker(AnalysisSettingsState settings) async {
    if (!mounted) return;
    try {
      // Проверка лимитов параллельно — bottom sheet не ждёт ответ API.
      final gateFuture = AiScanGate.ensureCanOpenScanner(context);

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Сделать снимок'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Выбрать из галереи'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;

      final ok = await gateFuture;
      if (!ok || !mounted) return;

      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        imageQuality: 78,
      );
      if (image == null || !mounted) return;
      final raw = await image.readAsBytes();
      if (!mounted) return;
      final bytes = await prepareImageForAiScan(raw);
      if (!mounted) return;
      await context.push(ScanResultRoute.path, extra: bytes);
      AiScanGate.invalidateCache();
      if (mounted) {
        setState(() => _hideMenuButtons = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось открыть камеру или галерею'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openDetails(Recipe recipe) async {
    final result = await Navigator.of(context, rootNavigator: true).push<RecipeDetailPopResult>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => DetailPage(
          recipe: recipe,
          isFavorite: _isFavorite(recipe.id),
          onToggle: () async => _toggleFavorite(recipe),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    if (result != null && mounted) {
      RecipeInteractionStats.apply(result);
      setState(() {});
    }
  }

  Future<void> _refreshRecommendations(AnalysisSettingsState settings) async {
    _cachedRecommendations = [];
    _cacheTimestamp = null;
    _sharedRecommendationsCache = [];
    _sharedCacheTimestamp = null;
    _lastSpoonacularQuotaExhausted = false;
    setState(() {
      _recommendationsLoadFailed = false;
    });
    final future = _fetchRecommendationsImmediate(settings);
    setState(() {
      _recommendationsFuture = future;
    });
    await future;
  }

  void _showIngredientsSearchDialog(AnalysisSettingsState settings) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Что приготовить из того, что есть?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText:
                'Введите продукты через запятую\nнапример: яйца, мука, молоко',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final q = controller.text.trim();
              Navigator.pop(ctx);
              if (q.isEmpty) return;
              _controller.text = q;
              ref
                  .read(searchControllerProvider.notifier)
                  .search(q, maxReadyTime: _selectedMaxReadyTime);
            },
            child: const Text('Искать'),
          ),
        ],
      ),
    );
  }

  void _showHistoryDrawer(BuildContext context) {
    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('dd MMM, HH:mm', 'ru');
    } catch (e) {
      dateFormat = DateFormat('dd MMM, HH:mm');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'История запросов',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Очистить историю?'),
                              content: const Text(
                                'Это действие удалит все локальные запросы и очистит историю на сервере.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Отмена'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Очистить'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await HistoryStorage.clear();
                            await ApiService.clearServerHistory();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('История очищена')),
                              );
                            }
                          }
                        },
                        child: const Text('Очистить'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  try {
                    return ValueListenableBuilder(
                      valueListenable: HistoryStorage.listenable(),
                      builder: (context, box, _) {
                        final entries = box.values
                            .toList()
                            .cast<SearchHistoryEntry>()
                            .reversed
                            .toList();
                        if (entries.isEmpty) {
                          return Center(
                            child: Text(
                              'Запросов пока нет. Найдите блюдо в разделе «Меню».',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              tileColor: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                              title: Text(entry.query),
                              subtitle: Text(
                                '${entry.mode.displayName} · ${dateFormat?.format(entry.timestamp) ?? entry.timestamp.toString()}',
                              ),
                              trailing: const Icon(Icons.north_west_rounded),
                              onTap: () async {
                                Navigator.of(context).pop();
                                _controller.text = entry.query;
                                await _runSearch();
                              },
                            );
                          },
                        );
                      },
                    );
                  } catch (e) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userVisibleError(
                                e,
                                fallback: 'История поиска недоступна',
                              ),
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    _showHistoryDrawer(this.context);
                                  }
                                });
                              },
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(menuRecommendationsRefreshProvider, (prev, next) {
      if (!mounted || next == 0 || prev == next) return;
      unawaited(_refreshRecommendations(ref.read(analysisSettingsProvider)));
    });

    final searchState = ref.watch(searchControllerProvider);
    final settings = ref.watch(analysisSettingsProvider);
    final subscriptionStatus = ref.watch(subscriptionStatusProvider);
    final canViewNutrition = RecipeNutritionAccess.resolve(
      subscription: subscriptionStatus.valueOrNull,
      viewerIsPlus: _lastViewerIsPlus,
    );

    // Listen to analysis settings changes
    ref.listen<AnalysisSettingsState>(
      analysisSettingsProvider,
      (previous, next) {
        if (previous?.mode != next.mode ||
            previous?.language != next.language) {
          _fetchRecommendations(next);
        }
      },
    );

    ref.listen(subscriptionStatusProvider, (previous, next) {
      final hadAi = RecipeTranslationAccess.fromSubscription(
        previous?.asData?.value,
      );
      final hasAi = RecipeTranslationAccess.fromSubscription(next.asData?.value);
      if (!hadAi && hasAi && mounted) {
        unawaited(_refreshRecommendations(settings));
      }
    });

    return Scaffold(
      extendBody: true,
      body: AppGradientBackground(
        child: SafeArea(
          bottom: false,
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n is ScrollUpdateNotification) {
                final hide = n.metrics.pixels > _scrollThreshold;
                if (hide != _hideMenuButtons && mounted) {
                  // Нельзя вызывать setState из уведомления прокрутки во время layout
                  // (внутри GridView это ломает _RenderLayoutBuilder).
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (hide != _hideMenuButtons) {
                      setState(() => _hideMenuButtons = hide);
                    }
                  });
                }
              }
              return false;
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _kMenuScreenEdgeGutter,
                    16,
                    _kMenuScreenEdgeGutter,
                    8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.history),
                        tooltip: 'История запросов',
                        onPressed: () => _showHistoryDrawer(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            controller: _controller,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _runSearch(),
                            decoration: InputDecoration(
                              hintText: 'Название блюда или ингредиенты',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _controller.clear();
                                        ref
                                            .read(searchControllerProvider
                                                .notifier)
                                            .reset();
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.category_outlined),
                        tooltip: 'Категории',
                        onPressed: () => context.push(CategoriesRoute.path),
                      ),
                    ],
                  ),
                ),
                // Кнопки скрываются при прокрутке вниз (duration всегда константа —
                // смена Duration.zero ↔ animated ломает RenderAnimatedSize при layout).
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: _hideMenuButtons
                      ? const SizedBox(width: double.infinity, height: 0)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(
                            _kMenuScreenEdgeGutter,
                            4,
                            _kMenuScreenEdgeGutter,
                            8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _MenuActionCard(
                                  icon: Icons.calendar_today_outlined,
                                  label: 'План питания',
                                  onTap: () => context.push(MealPlanRoute.path),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MenuActionCard(
                                  icon: Icons.shopping_cart_outlined,
                                  label: 'Список покупок',
                                  onTap: () =>
                                      context.push(ShoppingListRoute.path),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MenuActionCard(
                                  icon: Icons.camera_alt_outlined,
                                  label: 'Сканировать',
                                  onTap: () => _openMediaPicker(settings),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                // Активные категории
                Builder(
                  builder: (context) {
                    try {
                      return ValueListenableBuilder<List<CategoryFilter>>(
                        valueListenable: CategoryService.instance.filters,
                        builder: (context, filters, _) {
                          try {
                            final activeCategories =
                                CategoryService.instance.getActiveCategories();
                            if (activeCategories.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              height: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: _kMenuScreenEdgeGutter,
                              ),
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: activeCategories.map((category) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: Text(category.displayName),
                                      onDeleted: () {
                                        try {
                                          CategoryService.instance
                                              .toggleCategory(category, false);
                                        } catch (_) {
                                          // Ignore errors
                                        }
                                      },
                                      deleteIcon:
                                          const Icon(Icons.close, size: 18),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          } catch (e) {
                            return const SizedBox.shrink();
                          }
                        },
                      );
                    } catch (e) {
                      return const SizedBox.shrink();
                    }
                  },
                ),
                // Фильтр по времени готовки (только для поиска)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _kMenuScreenEdgeGutter,
                    4,
                    _kMenuScreenEdgeGutter,
                    4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Время готовки · для поиска',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                        _TimeFilterChip(
                          label: 'До 15 мин',
                          minutes: 15,
                          selected: _selectedMaxReadyTime == 15,
                          onTap: () => setState(() {
                            _selectedMaxReadyTime =
                                _selectedMaxReadyTime == 15 ? null : 15;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _TimeFilterChip(
                          label: 'До 30 мин',
                          minutes: 30,
                          selected: _selectedMaxReadyTime == 30,
                          onTap: () => setState(() {
                            _selectedMaxReadyTime =
                                _selectedMaxReadyTime == 30 ? null : 30;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _TimeFilterChip(
                          label: 'До 60 мин',
                          minutes: 60,
                          selected: _selectedMaxReadyTime == 60,
                          onTap: () => setState(() {
                            _selectedMaxReadyTime =
                                _selectedMaxReadyTime == 60 ? null : 60;
                          }),
                        ),
                        if (_selectedMaxReadyTime != null) ...[
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Сбросить время'),
                            onSelected: (_) =>
                                setState(() => _selectedMaxReadyTime = null),
                          ),
                        ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Быстрые фильтры (теги поиска)
                if (!searchState.hasSearched && _controller.text.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kMenuScreenEdgeGutter,
                      0,
                      _kMenuScreenEdgeGutter,
                      8,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _QuickFilterChip(
                              label: 'Быстро',
                              tags: 'quick-and-easy',
                              onTap: () => _applyQuickFilter(
                                'Быстро',
                                'quick-and-easy',
                                settings,
                                canViewNutrition: canViewNutrition,
                              )),
                          const SizedBox(width: 8),
                          _QuickFilterChip(
                              label: 'ЗОЖ',
                              tags: 'vegetarian',
                              onTap: () => _applyQuickFilter(
                                'ЗОЖ',
                                'vegetarian',
                                settings,
                                canViewNutrition: canViewNutrition,
                              )),
                          const SizedBox(width: 8),
                          _QuickFilterChip(
                              label: 'Низкокалорийное',
                              tags: 'low-calorie',
                              isNutritionFilter: true,
                              onTap: () => _applyQuickFilter(
                                'Низкокалорийное',
                                'low-calorie',
                                settings,
                                canViewNutrition: canViewNutrition,
                              )),
                          const SizedBox(width: 8),
                          _QuickFilterChip(
                              label: 'Высокий белок',
                              tags: 'high-protein',
                              isNutritionFilter: true,
                              onTap: () => _applyQuickFilter(
                                'Высокий белок',
                                'high-protein',
                                settings,
                                canViewNutrition: canViewNutrition,
                              )),
                          const SizedBox(width: 8),
                          _QuickFilterChip(
                            label: 'По ингредиентам',
                            tags: '',
                            onTap: () => _showIngredientsSearchDialog(settings),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (searchState.loading) const LinearProgressIndicator(),
                if (searchState.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kMenuScreenEdgeGutter,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            searchState.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            ref
                                .read(searchControllerProvider.notifier)
                                .resetError();
                            _runSearch();
                          },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _buildMainList(
                    settings: settings,
                    searchState: searchState,
                    canViewNutrition: canViewNutrition,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(searchControllerProvider.notifier).reset();
  }

  Widget _buildMainList({
    required AnalysisSettingsState settings,
    required SearchState searchState,
    required bool canViewNutrition,
  }) {
    if (searchState.loading &&
        searchState.hasSearched &&
        searchState.recipes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.recipes.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _runSearch(),
        child: _RecipesGrid(
          recipes: searchState.recipes,
          isFavorite: _isFavorite,
          onFavoriteTap: _toggleFavorite,
          onTap: _openDetails,
          favoritesLoading: _favoritesLoading,
          showNutritionValues: canViewNutrition,
          showFavoriteButton: _favoritesEnabled,
        ),
      );
    }

    if (searchState.hasSearched &&
        !searchState.loading &&
        searchState.error == null) {
      return RefreshIndicator(
        onRefresh: () async => _runSearch(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.search_off_rounded,
                title: 'Ничего не найдено',
                subtitle: _selectedMaxReadyTime != null
                    ? 'Попробуйте другой запрос или сбросьте фильтр по времени'
                    : 'Попробуйте другие слова или ингредиенты',
                action: TextButton(
                  onPressed: _clearSearch,
                  child: const Text('Сбросить поиск'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildRecommendations(
      settings,
      showNutritionValues: canViewNutrition,
    );
  }

  Widget _buildRecommendations(
    AnalysisSettingsState settings, {
    required bool showNutritionValues,
  }) {
    return RefreshIndicator(
      onRefresh: () => _refreshRecommendations(settings),
      child: FutureBuilder<RecommendationsResult>(
        future: _recommendationsFuture,
        builder: (context, snapshot) {
          final bottomInset = floatingBottomPadding(context);
          // Показываем кэш сразу, если есть, пока загружаются новые данные
          final RecommendationsResult effective;
          if (snapshot.hasData) {
            effective = snapshot.data!;
          } else if (_cachedRecommendations.isNotEmpty) {
            effective = _recommendationsFromCacheOnly();
          } else {
            effective = const RecommendationsResult(recipes: []);
          }
          final recipes = effective.recipes;
          if (recipes.isNotEmpty) {
            _warmImagesForRecipes(recipes);
          }
          final quotaExhausted = effective.spoonacularQuotaExhausted;
          final suggestPlusUpgrade = effective.suggestPlusUpgrade;

          // Если загрузка и нет кэша, показываем скелетон
          if (snapshot.connectionState == ConnectionState.waiting &&
              recipes.isEmpty) {
            return const ListSkeletonLoader(itemCount: 5);
          }

          if (snapshot.hasError && recipes.isEmpty) {
            // Проверяем, является ли ошибка ошибкой подключения к серверу
            final errorStr = snapshot.error.toString();
            final isConnectionError = errorStr.contains('Connection refused') ||
                errorStr.contains('Failed host lookup') ||
                errorStr.contains('Failed to fetch') ||
                errorStr.contains('TimeoutException') ||
                errorStr.contains('SocketException');

            // Для ошибок подключения к серверу не показываем ошибку, просто пустой список
            if (isConnectionError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  _kMenuScreenEdgeGutter,
                  16,
                  _kMenuScreenEdgeGutter,
                  24 + bottomInset,
                ),
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Сервер недоступен',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Рекомендации будут доступны после подключения к серверу',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.7),
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
              children: [
                AppEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не удалось загрузить',
                  subtitle: userVisibleError(
                    snapshot.error!,
                    fallback: 'Проверьте подключение',
                  ),
                  action: FilledButton(
                    onPressed: () => _refreshRecommendations(settings),
                    child: const Text('Повторить'),
                  ),
                ),
              ],
            );
          }
          if (recipes.isEmpty) {
            if (_recommendationsLoadFailed) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  _kMenuScreenEdgeGutter,
                  16,
                  _kMenuScreenEdgeGutter,
                  24 + bottomInset,
                ),
                children: [
                  AppEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Не удалось загрузить рекомендации',
                    subtitle: 'Проверьте сеть и потяните вниз для обновления',
                    action: FilledButton(
                      onPressed: () => _refreshRecommendations(settings),
                      child: const Text('Повторить'),
                    ),
                  ),
                ],
              );
            }
            final emptyText = quotaExhausted
                ? 'Лимит каталога на сегодня исчерпан. Тренды обновятся завтра; поиск по ингредиентам может быть недоступен.'
                : 'Пока тренды не найдены. Попробуйте поиск или быстрые фильтры выше.';
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                _kMenuScreenEdgeGutter,
                16,
                _kMenuScreenEdgeGutter,
                24 + bottomInset,
              ),
              children: [
                Text(
                  emptyText,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (suggestPlusUpgrade) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.push(
                        SubscriptionRoute.pathWithProduct('ai'),
                      ),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Выбрать тариф'),
                  ),
                ],
              ],
            );
          }
          final showTranslationUpsell = effective.recipeTranslationRequiresAi &&
              !RecipeTranslationAccess.fromSubscription(
                ref.watch(subscriptionStatusProvider).valueOrNull,
              );

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (showTranslationUpsell)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      _kMenuScreenEdgeGutter,
                      8,
                      _kMenuScreenEdgeGutter,
                      0,
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: const Text('Перевод рецептов — в тарифе AI'),
                        subtitle: Text(
                          'Названия и ингредиенты на '
                          '${languageDisplayName(settings.language)} без ручного перевода',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => context.push(
                            SubscriptionRoute.pathWithProduct('ai'),
                          ),
                          child: const Text('AI'),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _kMenuScreenEdgeGutter,
                  16,
                  _kMenuScreenEdgeGutter,
                  24 + bottomInset,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: _menuRecipeGridChildAspectRatio(
                      MediaQuery.sizeOf(context).width,
                      imageAspectRatio: _kMenuCardImageAspect,
                      textBlockHeight: _menuRecipeTextBlockHeight(context),
                    ),
                    crossAxisSpacing: _kMenuGridCrossAxisSpacing,
                    mainAxisSpacing: _kMenuGridCrossAxisSpacing,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final recipe = recipes[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 280),
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
                        child: ModernRecipeCard(
                          recipe: recipe,
                          imageAspectRatio: _kMenuCardImageAspect,
                          compact: true,
                          showNutritionValues: showNutritionValues,
                          isFavorite: _isFavorite(recipe.id),
                          onFavoriteTap: () => _toggleFavorite(recipe),
                          onTap: () => _openDetails(recipe),
                          favoritesLoading: _favoritesLoading,
                          showFavoriteButton: _favoritesEnabled,
                        ),
                      );
                    },
                    childCount: recipes.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Компактная кнопка под поиском в Menu (План питания, Список покупок).
class _MenuActionCard extends StatelessWidget {
  const _MenuActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 4,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeFilterChip extends StatelessWidget {
  const _TimeFilterChip({
    required this.label,
    required this.minutes,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _QuickFilterChip extends StatelessWidget {
  const _QuickFilterChip({
    required this.label,
    required this.tags,
    required this.onTap,
    this.isNutritionFilter = false,
  });
  final String label;
  final String tags;
  final VoidCallback onTap;
  final bool isNutritionFilter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (isNutritionFilter) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.workspace_premium_outlined,
              size: 16,
              color: scheme.primary,
            ),
          ],
        ],
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _RecipesGrid extends StatelessWidget {
  const _RecipesGrid({
    required this.recipes,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
    this.favoritesLoading = false,
    this.showNutritionValues = true,
    this.showFavoriteButton = true,
  });

  final List<Recipe> recipes;
  final bool Function(int) isFavorite;
  final Future<void> Function(Recipe) onFavoriteTap;
  final void Function(Recipe) onTap;
  final bool favoritesLoading;
  final bool showNutritionValues;
  final bool showFavoriteButton;

  @override
  Widget build(BuildContext context) {
    final bottomInset = floatingBottomPadding(context);
    if (recipes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomInset),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Список рецептов пуст. Попробуйте другой запрос.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _kMenuScreenEdgeGutter,
        16,
        _kMenuScreenEdgeGutter,
        16 + bottomInset,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: _menuRecipeGridChildAspectRatio(
          MediaQuery.sizeOf(context).width,
          imageAspectRatio: _kMenuCardImageAspect,
          textBlockHeight: _menuRecipeTextBlockHeight(context),
        ),
        crossAxisSpacing: _kMenuGridCrossAxisSpacing,
        mainAxisSpacing: _kMenuGridCrossAxisSpacing,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 280),
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
          child: ModernRecipeCard(
            recipe: recipe,
            imageAspectRatio: _kMenuCardImageAspect,
            compact: true,
            showNutritionValues: showNutritionValues,
            isFavorite: isFavorite(recipe.id),
            onFavoriteTap: () => onFavoriteTap(recipe),
            onTap: () => onTap(recipe),
            favoritesLoading: favoritesLoading,
            showFavoriteButton: showFavoriteButton,
          ),
        );
      },
    );
  }
}
