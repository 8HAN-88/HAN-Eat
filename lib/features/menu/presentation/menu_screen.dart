import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:intl/intl.dart';

import '../../../models/analysis_mode.dart';
import '../../../models/recipe.dart';
import '../../../models/search_history_entry.dart';
import '../../../models/recipe_category.dart';
import '../../../screens/detail_page.dart';
import '../../../services/api_service.dart';
import '../../../services/history_storage.dart';
import '../../../services/category_service.dart';
import '../../../widgets/modern_recipe_card.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../utils/image_url_helper.dart';
import '../../settings/application/analysis_mode_controller.dart';
import '../application/search_controller.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../../app/app_router.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  late Future<List<Recipe>> _recommendationsFuture;
  List<Recipe> _cachedRecommendations = []; // Кэш последних рекомендаций
  DateTime? _cacheTimestamp;
  static const _cacheDuration = Duration(minutes: 15); // Кэш на 15 минут для ускорения
  List<Recipe> _favorites = [];
  bool _favoritesLoading = false;
  bool _isListening = false;
  String? _selectedTags;
  String? _selectedIngredients;
  String? _activeFilterLabel;
  int? _selectedMaxReadyTime; // Фильтр по времени готовки (мин)
  bool _hideMenuButtons = false;
  static const _scrollThreshold = 60.0;

  @override
  void initState() {
    super.initState();
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
    
    // Если есть кэш, показываем его сразу (синхронно)
    if (_cachedRecommendations.isNotEmpty && 
        _cacheTimestamp != null && 
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      _recommendationsFuture = Future.value(_cachedRecommendations);
    } else {
      // Иначе начинаем загрузку
      _recommendationsFuture = _fetchRecommendationsImmediate(settings);
    }
    
    // Загружаем избранное параллельно (не блокируем UI)
    _loadFavorites();
  }
  
  Future<List<Recipe>> _fetchRecommendationsImmediate(AnalysisSettingsState settings) async {
    // Если есть кэш и он еще актуален, возвращаем его сразу
    if (_cachedRecommendations.isNotEmpty && 
        _cacheTimestamp != null && 
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      return _cachedRecommendations;
    }
    
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
    final tagsString = activeTags.isNotEmpty 
        ? activeTags.join(',') 
        : (_selectedTags ?? '');
    
    try {
      final recipes = await ApiService.fetchRecommendations(
        limit: 8,
        tags: tagsString.isNotEmpty ? tagsString : null,
        ingredients: _selectedIngredients,
        mode: settings.mode,
        language: settings.language,
      );
      
      // Сохраняем в кэш
      if (mounted) {
        _cachedRecommendations = recipes;
        _cacheTimestamp = DateTime.now();
      }
      
      return recipes;
    } catch (e) {
      // При ошибке подключения к серверу возвращаем пустой список или кэш
      if (kDebugMode) {
        debugPrint('Error fetching recommendations: $e');
      }
      // Если есть кэш, возвращаем его
      if (_cachedRecommendations.isNotEmpty) {
        return _cachedRecommendations;
      }
      // Иначе возвращаем пустой список
      return [];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    // Не показываем индикатор загрузки для избранного, чтобы не блокировать UI
    // Загружаем в фоне
    try {
      final favs = await ApiService.getFavorites().timeout(
        const Duration(seconds: 5),
        onTimeout: () => <Recipe>[], // Возвращаем пустой список при таймауте
      );
      if (!mounted) return;
      setState(() {
        _favorites = favs;
        _favoritesLoading = false;
      });
    } catch (e) {
      // Игнорируем ошибки загрузки избранного, чтобы не блокировать основной UI
      if (mounted) {
        setState(() => _favoritesLoading = false);
      }
    }
  }

  bool _isFavorite(int id) => _favorites.any((r) => r.id == id);

  Future<void> _toggleFavorite(Recipe recipe) async {
    // Проверяем, что у рецепта есть ID
    if (recipe.id == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: у рецепта отсутствует ID'),
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
      String userMessage = 'Ошибка при добавлении в избранное: $e';

      // Обработка различных типов ошибок
      if (errorMsg.contains('recipe has no id') || errorMsg.contains('no id')) {
        userMessage = 'Ошибка: у рецепта отсутствует ID. Попробуйте обновить страницу.';
      } else if (errorMsg.contains('daily points limit') ||
          errorMsg.contains('points limit') ||
          errorMsg.contains('402') ||
          errorMsg.contains('unauthorized') ||
          errorMsg.contains('401')) {
        userMessage = 'Ошибка доступа. Проверьте подключение к серверу.';
      } else if (errorMsg.contains('network') || errorMsg.contains('connection')) {
        userMessage = 'Ошибка сети. Проверьте подключение к интернету.';
      } else if (errorMsg.contains('timeout')) {
        userMessage = 'Превышено время ожидания. Попробуйте позже.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage),
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    List<String> activeTags = [];
    try {
      activeTags = CategoryService.instance.getSpoonacularTagsForActiveCategories();
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
    
    setState(() {
      _recommendationsFuture = _fetchRecommendationsImmediate(settings);
    });
  }

  Future<void> _runSearchFromHistory(String query) async {
    _controller.text = query;
    await _runSearch();
  }

  void _applyQuickFilter(String label, String tag, AnalysisSettingsState settings) {
    _controller.text = label;
    final maxMin = label == 'Быстро' ? 15 : _selectedMaxReadyTime;
    ref.read(searchControllerProvider.notifier).searchByTag(label, tag, maxReadyTime: maxMin);
  }

  Future<void> _openMediaPicker(AnalysisSettingsState settings) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
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
    if (source == null) return;
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1440,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    context.push(ScanResultRoute.path, extra: bytes);
  }

  Future<void> _toggleVoice(AnalysisSettingsState settings) async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка распознавания речи: ${error.errorMsg}')),
          );
        }
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Микрофон недоступен')),
      );
      return;
    }
    final locale = _speechLocale(settings.language);
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: locale,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.recognizedWords;
        });
        if (result.finalResult) {
          _speech.stop();
          setState(() => _isListening = false);
          _runSearch();
        }
      },
    );
  }

  void _openDetails(Recipe recipe) {
    Navigator.of(context).push(
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
  }

  Future<void> _refreshRecommendations(AnalysisSettingsState settings) async {
    _cachedRecommendations = [];
    _cacheTimestamp = null;
    setState(() {
      _recommendationsFuture = _fetchRecommendationsImmediate(settings);
    });
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
            hintText: 'Введите продукты через запятую\nнапример: яйца, мука, молоко',
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
              ref.read(searchControllerProvider.notifier).search(q, maxReadyTime: _selectedMaxReadyTime);
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
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Отмена'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(true),
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
                                const SnackBar(content: Text('История очищена')),
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
                              'Запросов пока нет. Найдите блюдо в разделе "Menu".',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              tileColor: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.outlineVariant,
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
                      child: Text(
                        'История не инициализирована: $e',
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
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
    final searchState = ref.watch(searchControllerProvider);
    final settings = ref.watch(analysisSettingsProvider);
    
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

    return Scaffold(
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n is ScrollUpdateNotification) {
              final hide = n.metrics.pixels > _scrollThreshold;
              if (hide != _hideMenuButtons && mounted) {
                setState(() => _hideMenuButtons = hide);
              }
            }
            return false;
          },
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      decoration: InputDecoration(
                        hintText: 'Это поле для ввода запроса',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                color: _isListening
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              onPressed: () => _toggleVoice(settings),
                            ),
                            if (_controller.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _controller.clear();
                                  ref.read(searchControllerProvider.notifier).reset();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.category_outlined),
                  tooltip: 'Категории',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CategoriesScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Кнопки скрываются при прокрутке вниз
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _hideMenuButtons
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                            onTap: () => context.push(ShoppingListRoute.path),
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
                      final activeCategories = CategoryService.instance.getActiveCategories();
                      if (activeCategories.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: activeCategories.map((category) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: Text(category.displayName),
                                onDeleted: () {
                                  try {
                                    CategoryService.instance.toggleCategory(category, false);
                                  } catch (_) {
                                    // Ignore errors
                                  }
                                },
                                deleteIcon: const Icon(Icons.close, size: 18),
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
          // Фильтр по времени готовки
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TimeFilterChip(
                    label: 'До 15 мин',
                    minutes: 15,
                    selected: _selectedMaxReadyTime == 15,
                    onTap: () => setState(() {
                      _selectedMaxReadyTime = _selectedMaxReadyTime == 15 ? null : 15;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _TimeFilterChip(
                    label: 'До 30 мин',
                    minutes: 30,
                    selected: _selectedMaxReadyTime == 30,
                    onTap: () => setState(() {
                      _selectedMaxReadyTime = _selectedMaxReadyTime == 30 ? null : 30;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _TimeFilterChip(
                    label: 'До 60 мин',
                    minutes: 60,
                    selected: _selectedMaxReadyTime == 60,
                    onTap: () => setState(() {
                      _selectedMaxReadyTime = _selectedMaxReadyTime == 60 ? null : 60;
                    }),
                  ),
                  if (_selectedMaxReadyTime != null) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Сбросить время'),
                      onSelected: (_) => setState(() => _selectedMaxReadyTime = null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Быстрые фильтры (теги поиска)
          if (!searchState.hasSearched && _controller.text.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _QuickFilterChip(label: 'Быстро', tags: 'quick-and-easy', onTap: () => _applyQuickFilter('Быстро', 'quick-and-easy', settings)),
                    const SizedBox(width: 8),
                    _QuickFilterChip(label: 'ЗОЖ', tags: 'vegetarian', onTap: () => _applyQuickFilter('ЗОЖ', 'vegetarian', settings)),
                    const SizedBox(width: 8),
                    _QuickFilterChip(label: 'Низкокалорийное', tags: 'low-calorie', onTap: () => _applyQuickFilter('Низкокалорийное', 'low-calorie', settings)),
                    const SizedBox(width: 8),
                    _QuickFilterChip(label: 'Высокий белок', tags: 'high-protein', onTap: () => _applyQuickFilter('Высокий белок', 'high-protein', settings)),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      ref.read(searchControllerProvider.notifier).resetError();
                      _runSearch();
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: searchState.recipes.isNotEmpty
                ? _RecipesGrid(
                    recipes: searchState.recipes,
                    isFavorite: _isFavorite,
                    onFavoriteTap: _toggleFavorite,
                    onTap: _openDetails,
                    favoritesLoading: _favoritesLoading,
                  )
                : _buildRecommendations(settings),
          ),
        ],
        ),
      ),
      ),
    );
  }

  Widget _buildRecommendations(AnalysisSettingsState settings) {
    return RefreshIndicator(
      onRefresh: () => _refreshRecommendations(settings),
      child: FutureBuilder<List<Recipe>>(
        future: _recommendationsFuture,
        builder: (context, snapshot) {
          // Показываем кэш сразу, если есть, пока загружаются новые данные
          final recipes = snapshot.hasData 
              ? snapshot.data! 
              : (_cachedRecommendations.isNotEmpty 
                  ? _cachedRecommendations 
                  : <Recipe>[]);
          
          // Если загрузка и нет кэша, показываем скелетон
          if (snapshot.connectionState == ConnectionState.waiting && recipes.isEmpty) {
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.wifi_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Сервер недоступен',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Рекомендации будут доступны после подключения к серверу',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
            
            // Для других ошибок показываем сообщение
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Не удалось загрузить рекомендации: ${snapshot.error}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _refreshRecommendations(settings),
                  child: const Text('Повторить'),
                ),
              ],
            );
          }
          if (recipes.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  'Пока тренды не найдены. Попробуйте выбрать другой фильтр или выполнить поиск.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            );
          }
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.80,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final recipe = recipes[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 300 + (index * 50)),
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
                          isFavorite: _isFavorite(recipe.id),
                          onFavoriteTap: () => _toggleFavorite(recipe),
                          onTap: () => _openDetails(recipe),
                          favoritesLoading: _favoritesLoading,
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w500,
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
  });
  final String label;
  final String tags;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
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
  });

  final List<Recipe> recipes;
  final bool Function(int) isFavorite;
  final Future<void> Function(Recipe) onFavoriteTap;
  final void Function(Recipe) onTap;
  final bool favoritesLoading;

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'История пустая. Найдите рецепт по ингредиентам или воспользуйтесь рекомендациями.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.80,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 50)),
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
            isFavorite: isFavorite(recipe.id),
            onFavoriteTap: () => onFavoriteTap(recipe),
            onTap: () => onTap(recipe),
            favoritesLoading: favoritesLoading,
          ),
        );
      },
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
    required this.favoritesLoading,
  });

  final Recipe recipe;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;
  final bool favoritesLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Всегда используем перевод если он есть (из настроек)
    final title = recipe.translatedTitle?.isNotEmpty == true
        ? recipe.translatedTitle!
        : recipe.title;
    final ingredients = recipe.translatedIngredients?.isNotEmpty == true
        ? recipe.translatedIngredients!
        : recipe.ingredients;
    final subtitle = recipe.summary?.isNotEmpty == true
        ? recipe.summary!
        : '${ingredients.take(3).join(', ')}...';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: recipe.image == null
                    ? Container(
                        width: 88,
                        height: 88,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported),
                      )
                    : Image.network(
                        getOptimizedImageUrl(recipe.image!),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            width: 88,
                            height: 88,
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
                          return Container(
                            width: 88,
                            height: 88,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.error_outline),
                          );
                        },
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (recipe.calories != null)
                          Chip(
                            label: Text('${recipe.calories} ккал'),
                            avatar: const Icon(Icons.local_fire_department),
                          ),
                        if (_getProtein(recipe) != null)
                          Chip(
                            label: Text('${_getProtein(recipe)!.toStringAsFixed(1)} г белков'),
                            avatar: const Icon(Icons.fitness_center),
                          ),
                        if (_getFat(recipe) != null)
                          Chip(
                            label: Text('${_getFat(recipe)!.toStringAsFixed(1)} г жиров'),
                            avatar: const Icon(Icons.opacity),
                          ),
                        if (_getCarbs(recipe) != null)
                          Chip(
                            label: Text('${_getCarbs(recipe)!.toStringAsFixed(1)} г углеводов'),
                            avatar: const Icon(Icons.eco),
                          ),
                        Chip(
                          label:
                              Text('Ингредиентов: ${ingredients.length}'),
                          avatar: const Icon(Icons.shopping_basket_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: favoritesLoading ? null : onFavoriteTap,
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
}

String _speechLocale(String languageCode) {
  switch (languageCode.toLowerCase()) {
    case 'ru':
      return 'ru_RU';
    case 'es':
      return 'es_ES';
    case 'de':
      return 'de_DE';
    case 'fr':
      return 'fr_FR';
    case 'en':
    default:
      return 'en_US';
  }
}
