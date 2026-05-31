import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/search_service.dart';
import '../../../../models/post_model.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../../../widgets/post_card_skeleton.dart';
import '../../../../app/app_router.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Подставляется из `?q=` (например из рилсов по хештегу).
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;
  bool _showFilters = false;
  String? _error;
  
  // Результаты поиска
  List<PostModel> _posts = [];
  int _total = 0;
  int _offset = 0;
  static const int _limit = 20;
  
  // Фильтры
  String? _selectedPostType;
  String? _selectedSortBy = 'relevance';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _minLikes;
  int? _minComments;
  List<String> _selectedTags = [];
  
  // Автодополнение
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchController.text = q;
        _performSearch();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length >= 2) {
      _loadSuggestions(query);
    } else {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
    }
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final suggestions = await SearchService.getSuggestions(query: query);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = true;
        });
      }
    } catch (e) {
      // Игнорируем ошибки автодополнения
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _performSearch({bool reset = true}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _posts = [];
        _total = 0;
        _error = null;
      });
      return;
    }

    if (reset) {
      _offset = 0;
      _posts = [];
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _showSuggestions = false;
    });

    try {
      final response = await SearchService.searchPosts(
        query: query,
        postType: _selectedPostType,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        minLikes: _minLikes,
        minComments: _minComments,
        sortBy: _selectedSortBy!,
        limit: _limit,
        offset: _offset,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _posts = response.posts;
          } else {
            _posts.addAll(response.posts);
          }
          _total = response.total;
          _offset = _offset + response.posts.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка поиска: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _offset >= _total) return;
    await _performSearch(reset: false);
  }

  void _clearFilters() {
    setState(() {
      _selectedPostType = null;
      _selectedSortBy = 'relevance';
      _dateFrom = null;
      _dateTo = null;
      _minLikes = null;
      _minComments = null;
      _selectedTags = [];
    });
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: () {
              setState(() => _showFilters = !_showFilters);
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              // Поисковая строка
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Поиск постов, рецептов...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _posts = [];
                                    _total = 0;
                                    _error = null;
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (_) => _performSearch(),
                      onTap: () {
                        if (_searchController.text.length >= 2) {
                          setState(() => _showSuggestions = true);
                        }
                      },
                    ),
                    // Автодополнение
                    if (_showSuggestions && _suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              leading: const Icon(Icons.search, size: 20),
                              title: Text(suggestion),
                              onTap: () {
                                _searchController.text = suggestion;
                                setState(() => _showSuggestions = false);
                                _performSearch();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (_showFilters)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (constraints.maxHeight * 0.48).clamp(120.0, 420.0),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 8,
                    ),
                    child: _buildFilters(),
                  ),
                ),
              Expanded(
                child: _buildResults(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Фильтры',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Тип поста
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Все'),
                selected: _selectedPostType == null,
                onSelected: (selected) {
                  setState(() => _selectedPostType = null);
                  _performSearch();
                },
              ),
              FilterChip(
                label: const Text('Фото'),
                selected: _selectedPostType == 'photo',
                onSelected: (selected) {
                  setState(() => _selectedPostType = selected ? 'photo' : null);
                  _performSearch();
                },
              ),
              FilterChip(
                label: const Text('Рецепты'),
                selected: _selectedPostType == 'recipe',
                onSelected: (selected) {
                  setState(() => _selectedPostType = selected ? 'recipe' : null);
                  _performSearch();
                },
              ),
              FilterChip(
                label: const Text('Рилсы'),
                selected: _selectedPostType == 'reel',
                onSelected: (selected) {
                  setState(() => _selectedPostType = selected ? 'reel' : null);
                  _performSearch();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Сортировка (отдельная строка + сегменты на всю ширину — без переноса «Релевантность» столбиком)
          Text(
            'Сортировка',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'relevance',
                label: Text(
                  'Релевантность',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              ButtonSegment(
                value: 'date',
                label: Text('Дата'),
              ),
              ButtonSegment(
                value: 'popularity',
                label: Text(
                  'Популярность',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            selected: {_selectedSortBy!},
            onSelectionChanged: (selection) {
              setState(() => _selectedSortBy = selection.first);
              _performSearch();
            },
          ),
          const SizedBox(height: 12),
          // Дополнительные фильтры
          ExpansionTile(
            title: const Text('Дополнительные фильтры'),
            children: [
              // Минимальные лайки
              ListTile(
                title: const Text('Минимум лайков'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: _minLikes?.toString() ?? '0',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _minLikes = value.isEmpty ? null : int.tryParse(value);
                      });
                    },
                  ),
                ),
              ),
              // Минимальные комментарии
              ListTile(
                title: const Text('Минимум комментариев'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: _minComments?.toString() ?? '0',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _minComments = value.isEmpty ? null : int.tryParse(value);
                      });
                    },
                  ),
                ),
              ),
              // Выбор дат
              ListTile(
                title: const Text('Дата от'),
                trailing: TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _dateFrom = date);
                    }
                  },
                  child: Text(
                    _dateFrom != null
                        ? '${_dateFrom!.day}.${_dateFrom!.month}.${_dateFrom!.year}'
                        : 'Выбрать',
                  ),
                ),
              ),
              ListTile(
                title: const Text('Дата до'),
                trailing: TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: _dateFrom ?? DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _dateTo = date);
                    }
                  },
                  child: Text(
                    _dateTo != null
                        ? '${_dateTo!.day}.${_dateTo!.month}.${_dateTo!.year}'
                        : 'Выбрать',
                  ),
                ),
              ),
              // Кнопка применить
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _performSearch,
                  child: const Text('Применить фильтры'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading && _posts.isEmpty) {
      return const PostListSkeletonLoader(itemCount: 5);
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _performSearch,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Введите запрос для поиска',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ищите посты, рецепты, ингредиентам...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _performSearch(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final post = _posts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NewPostCard(
              post: post,
              onCommentTap: () =>
                  context.push(PostCommentsRoute.pathFor(post.id)),
              onPostDeleted: () {
                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                });
              },
              onAuthorTap: () {
                context.push(ProfileRoute.withUserId(post.userId));
              },
            ),
          );
        },
      ),
    );
  }
}

