import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:han_eat/services/search_service.dart';
import 'package:han_eat/services/chat_service.dart';
import '../../chat/application/chat_open_direct.dart';
import '../../chat/application/chat_thread_prefetch.dart';
import 'package:han_eat/services/channel_service.dart';
import 'package:han_eat/services/global_search_cache.dart';
import 'package:han_eat/services/server_config.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/models/chat_models.dart';
import '../../feed/presentation/new_post_card.dart';
import 'package:han_eat/widgets/post_card_skeleton.dart';
import 'package:han_eat/widgets/highlighted_text.dart';
import 'package:han_eat/widgets/app_gradient_background.dart';
import 'package:han_eat/app/app_router.dart';
import '../../../utils/api_error_parser.dart';
import '../application/search_scope.dart';

enum _MainSearchTab { all, posts, people, channels, messages }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialQuery,
    this.scope,
    this.feedType,
    this.followingOnly = false,
  });

  /// Подставляется из `?q=` (например из рилсов по хештегу).
  final String? initialQuery;
  final SearchScope? scope;
  final String? feedType;
  final bool followingOnly;

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
  List<ChatUserSearchItem> _people = [];
  List<Channel> _channels = [];
  List<ChatMessageSearchItem> _messageHits = [];
  List<String> _recentQueries = [];
  int _total = 0;
  int _offset = 0;
  static const int _limit = 20;

  _MainSearchTab _mainTab = _MainSearchTab.all;

  // Фильтры
  String? _selectedPostType;
  String? _selectedSortBy = 'relevance';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _minLikes;
  int? _minComments;
  List<String> _selectedTags = [];
  String? _selectedMessageType;

  // Автодополнение
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  late final bool _followingOnly;
  late final bool _lockPostTypeFilter;

  String get _screenTitle => widget.scope?.title ?? 'Поиск';

  String get _searchHint =>
      widget.scope?.hint ?? 'Посты, люди, рилсы, каналы…';

  bool get _channelsOnlyMode => widget.scope == SearchScope.channels;

  bool get _chatsHubMode => widget.scope?.usesChatsHubSearch ?? false;

  bool get _unifiedPeopleSearch =>
      !_channelsOnlyMode &&
      !_chatsHubMode &&
      (widget.scope == null || widget.scope == SearchScope.main);

  bool get _searchPosts =>
      !_channelsOnlyMode &&
      !_chatsHubMode &&
      (!_unifiedPeopleSearch ||
          _mainTab == _MainSearchTab.all ||
          _mainTab == _MainSearchTab.posts);

  bool get _searchPeople =>
      (_chatsHubMode && _mainTab == _MainSearchTab.people) ||
      (_unifiedPeopleSearch &&
          (_mainTab == _MainSearchTab.all ||
              _mainTab == _MainSearchTab.people));

  bool get _searchChannels =>
      _channelsOnlyMode ||
      (_chatsHubMode && _mainTab == _MainSearchTab.channels) ||
      (_unifiedPeopleSearch &&
          (_mainTab == _MainSearchTab.all ||
              _mainTab == _MainSearchTab.channels));

  bool get _searchMessages =>
      _chatsHubMode && _mainTab == _MainSearchTab.messages;

  static const _historyKey = 'main_search_history_v1';

  @override
  void initState() {
    super.initState();
    _followingOnly = widget.followingOnly;
    _selectedPostType = feedFilterToPostType(widget.feedType);
    _lockPostTypeFilter = widget.feedType != null && widget.feedType != 'all';
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _loadRecentQueries();
    if (_channelsOnlyMode) _mainTab = _MainSearchTab.channels;
    if (_chatsHubMode) _mainTab = _MainSearchTab.people;
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

  Future<void> _loadRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? [];
    if (mounted) setState(() => _recentQueries = raw.take(12).toList());
  }

  Future<void> _rememberQuery(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final next = [q, ..._recentQueries.where((e) => e != q)].take(12).toList();
    _recentQueries = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
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

  String _buildSearchCacheKey(String query) {
    return GlobalSearchCache.buildKey(
      scope: widget.scope?.name,
      mainTab: _mainTab.name,
      query: query,
      messageType: _selectedMessageType,
      followingOnly: _followingOnly,
      postType: _selectedPostType,
      sortBy: _selectedSortBy,
      tags: _selectedTags.isNotEmpty ? _selectedTags.join(',') : null,
      dateFrom: _dateFrom?.toIso8601String().split('T').first,
      dateTo: _dateTo?.toIso8601String().split('T').first,
      minLikes: _minLikes,
      minComments: _minComments,
    );
  }

  void _applyCachedSearch(GlobalSearchCachedResult cached) {
    _posts = List<PostModel>.from(cached.posts);
    _people = List<ChatUserSearchItem>.from(cached.people);
    _channels = List<Channel>.from(cached.channels);
    _total = cached.total;
    _offset = cached.posts.length;
  }

  Future<void> _performSearch({bool reset = true}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (_chatsHubMode && _mainTab == _MainSearchTab.channels) {
        if (reset) {
          setState(() {
            _isLoading = true;
            _error = null;
            _people = [];
            _channels = [];
            _messageHits = [];
          });
        }
        try {
          final resp = await ChannelService.listChannels(
            limit: 40,
            catalog: true,
          );
          if (!mounted) return;
          setState(() {
            _channels = resp.items;
            _isLoading = false;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _error = userVisibleError(e);
            _isLoading = false;
          });
        }
        return;
      }
      setState(() {
        _posts = [];
        _people = [];
        _channels = [];
        _messageHits = [];
        _total = 0;
        _error = null;
        _isLoading = false;
      });
      return;
    }

    if (reset) {
      _offset = 0;
      _posts = [];
      if (_searchPeople) _people = [];
      if (_searchChannels) _channels = [];
      if (_searchMessages) _messageHits = [];
    }

    GlobalSearchCachedResult? cachedResult;
    if (reset) {
      cachedResult = GlobalSearchCache.peek(_buildSearchCacheKey(query));
      if (cachedResult != null && cachedResult.hasContent) {
        _applyCachedSearch(cachedResult);
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _showSuggestions = false;
    });

    try {


      List<ChatUserSearchItem>? peopleResult;
      if (_searchPeople && reset) {
        try {
          peopleResult = await ChatService.searchUsers(query);
        } catch (e) {
          if (_mainTab == _MainSearchTab.people) rethrow;
        }
      }

      List<Channel>? channelsResult;
      if (_searchChannels && reset) {
        try {
          final resp = await ChannelService.listChannels(
            search: query,
            limit: 30,
            catalog: true,
          );
          channelsResult = resp.items;
        } catch (e) {
          if (_mainTab == _MainSearchTab.channels || _channelsOnlyMode) {
            rethrow;
          }
        }
      }

      List<ChatMessageSearchItem>? messageResult;
      if (_searchMessages && reset) {
        try {
          messageResult = await ChatService.searchMessages(
            query: query,
            limit: 40,
            type: _selectedMessageType,
          );
        } catch (e) {
          rethrow;
        }
      }

      if (!_searchPosts) {
        if (mounted) {
          setState(() {
            if (peopleResult != null) _people = peopleResult;
            if (channelsResult != null) _channels = channelsResult;
            if (messageResult != null) _messageHits = messageResult;
            _isLoading = false;
          });
          if (reset) {
            unawaited(
              GlobalSearchCache.save(
                _buildSearchCacheKey(query),
                GlobalSearchCachedResult(
                  people: peopleResult ?? const [],
                  channels: channelsResult ?? const [],
                ),
              ),
            );
            unawaited(_rememberQuery(query));
          }
        }
        return;
      }

      final response = await SearchService.searchPosts(
        query: query,
        postType: _selectedPostType,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        minLikes: _minLikes,
        minComments: _minComments,
        sortBy: _selectedSortBy!,
        followingOnly: _followingOnly,
        limit: _limit,
        offset: _offset,
      );

      if (mounted) {
        setState(() {
          if (reset && peopleResult != null) {
            _people = peopleResult;
          }
          if (reset && channelsResult != null) {
            _channels = channelsResult;
          }
          if (reset) {
            _posts = response.posts;
          } else {
            _posts.addAll(response.posts);
          }
          _total = response.total;
          _offset = _offset + response.posts.length;
          _isLoading = false;
        });
        if (reset) {
          unawaited(
            GlobalSearchCache.save(
              _buildSearchCacheKey(query),
              GlobalSearchCachedResult(
                posts: response.posts,
                total: response.total,
                people: peopleResult ?? const [],
                channels: channelsResult ?? const [],
              ),
            ),
          );
          unawaited(_rememberQuery(query));
        }
      }
    } catch (e) {
      if (mounted) {
        if (cachedResult != null && cachedResult.hasContent) {
          _applyCachedSearch(cachedResult);
          setState(() {
            _error = null;
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _error = userVisibleError(e, fallback: 'Не удалось выполнить поиск');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_searchPosts || _offset >= _total) return;
    await _performSearch(reset: false);
  }

  Future<void> _openPersonChat(ChatUserSearchItem user) async {
    try {
      final conv = await ChatOpenDirect.openNow(user.id, peer: user.brief);
      if (!mounted) return;
      context.push(ChatThreadRoute.pathFor(conv), extra: conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
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
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(_screenTitle),
          actions: [
            if (!_unifiedPeopleSearch || _mainTab != _MainSearchTab.people)
              IconButton(
                icon: Icon(_showFilters
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined),
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
                          hintText: _searchHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _posts = [];
                                      _people = [];
                                      _channels = [];
                                      _messageHits = [];
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
                      if (_chatsHubMode) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<_MainSearchTab>(
                          segments: const [
                            ButtonSegment(
                              value: _MainSearchTab.people,
                              label: Text('Люди'),
                              icon:
                                  Icon(Icons.person_search_outlined, size: 18),
                            ),
                            ButtonSegment(
                              value: _MainSearchTab.channels,
                              label: Text('Каналы'),
                              icon: Icon(Icons.explore_outlined, size: 18),
                            ),
                            ButtonSegment(
                              value: _MainSearchTab.messages,
                              label: Text('Сообщения'),
                              icon: Icon(Icons.forum_outlined, size: 18),
                            ),
                          ],
                          selected: {_mainTab},
                          onSelectionChanged: (selection) {
                            setState(() => _mainTab = selection.first);
                            _performSearch();
                          },
                        ),
                      ] else if (_unifiedPeopleSearch) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<_MainSearchTab>(
                          segments: const [
                            ButtonSegment(
                              value: _MainSearchTab.all,
                              label: Text('Все'),
                            ),
                            ButtonSegment(
                              value: _MainSearchTab.posts,
                              label: Text('Посты'),
                            ),
                            ButtonSegment(
                              value: _MainSearchTab.people,
                              label: Text('Люди'),
                            ),
                            ButtonSegment(
                              value: _MainSearchTab.channels,
                              label: Text('Каналы'),
                            ),
                          ],
                          selected: {_mainTab},
                          onSelectionChanged: (selection) {
                            setState(() => _mainTab = selection.first);
                            if (_searchController.text.trim().isNotEmpty) {
                              _performSearch();
                            }
                          },
                        ),
                      ],
                      if (_chatsHubMode &&
                          _mainTab == _MainSearchTab.messages) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildMessageTypeChip(null, 'Все'),
                              _buildMessageTypeChip('text', 'Текст'),
                              _buildMessageTypeChip('image', 'Фото'),
                              _buildMessageTypeChip('video', 'Видео'),
                              _buildMessageTypeChip('video_note', 'Кружки'),
                              _buildMessageTypeChip('file', 'Файлы'),
                              _buildMessageTypeChip('voice', 'Голос'),
                              _buildMessageTypeChip('sticker', 'Стикеры'),
                              _buildMessageTypeChip('location', 'Гео'),
                              _buildMessageTypeChip('poll', 'Опросы'),
                            ],
                          ),
                        ),
                      ],
                      if (_searchController.text.trim().isEmpty &&
                          _recentQueries.isNotEmpty)
                        _buildRecentQueries(),
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
                      maxHeight:
                          (constraints.maxHeight * 0.48).clamp(120.0, 420.0),
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
          if (!_lockPostTypeFilter) ...[
            const SizedBox(height: 12),
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
                    setState(
                        () => _selectedPostType = selected ? 'photo' : null);
                    _performSearch();
                  },
                ),
                FilterChip(
                  label: const Text('Рилсы'),
                  selected: _selectedPostType == 'reel',
                  onSelected: (selected) {
                    setState(
                        () => _selectedPostType = selected ? 'reel' : null);
                    _performSearch();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
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
                        _minComments =
                            value.isEmpty ? null : int.tryParse(value);
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

  Widget _buildRecentQueries() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recentQueries
              .map(
                (q) => ActionChip(
                  label: Text(q),
                  onPressed: () {
                    _searchController.text = q;
                    _performSearch();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final query = _searchController.text.trim();
    final showPeople = _searchPeople && _people.isNotEmpty;
    final showPosts = _searchPosts && _posts.isNotEmpty;
    final showChannels = _searchChannels && _channels.isNotEmpty;
    final showMessages = _searchMessages && _messageHits.isNotEmpty;
    final peopleOnly = (_chatsHubMode && _mainTab == _MainSearchTab.people) ||
        (_unifiedPeopleSearch && _mainTab == _MainSearchTab.people);
    final channelsOnly = _channelsOnlyMode ||
        (_chatsHubMode && _mainTab == _MainSearchTab.channels) ||
        (_unifiedPeopleSearch && _mainTab == _MainSearchTab.channels);
    final messagesOnly = _chatsHubMode && _mainTab == _MainSearchTab.messages;

    if (_isLoading &&
        _posts.isEmpty &&
        _people.isEmpty &&
        _channels.isEmpty &&
        _messageHits.isEmpty) {
      if (peopleOnly) {
        return const Center(child: CircularProgressIndicator());
      }
      if (messagesOnly) {
        return const Center(child: CircularProgressIndicator());
      }
      return const PostListSkeletonLoader(itemCount: 5);
    }

    if (_error != null &&
        _posts.isEmpty &&
        _people.isEmpty &&
        _channels.isEmpty &&
        _messageHits.isEmpty) {
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

    if (_posts.isEmpty &&
        _people.isEmpty &&
        _channels.isEmpty &&
        _messageHits.isEmpty &&
        !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              query.isEmpty ? Icons.search_off : Icons.person_search_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              query.isEmpty
                  ? (_chatsHubMode && _mainTab == _MainSearchTab.people
                      ? 'Введите имя или @username'
                      : 'Введите запрос для поиска')
                  : 'Ничего не найдено',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _searchHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: const Text('Очистить запрос'),
              ),
            ],
          ],
        ),
      );
    }

    if (peopleOnly) {
      return RefreshIndicator(
        onRefresh: () => _performSearch(),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _people.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) =>
              _buildPersonTile(_people[index], query),
        ),
      );
    }

    if (channelsOnly) {
      return RefreshIndicator(
        onRefresh: () => _performSearch(),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _channels.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) =>
              _buildChannelTile(_channels[index], query),
        ),
      );
    }

    if (messagesOnly) {
      return RefreshIndicator(
        onRefresh: () => _performSearch(),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _messageHits.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, index) =>
              _buildMessageHitTile(_messageHits[index], query),
        ),
      );
    }

    final children = <Widget>[];

    if (showPeople) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Люди',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
      for (final person in _people) {
        children.add(_buildPersonTile(person, query));
      }
    }

    if (showChannels) {
      if (showPeople || showPosts) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Каналы',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
      }
      for (final channel in _channels) {
        children.add(_buildChannelTile(channel, query));
      }
    }

    if (showPosts) {
      if (showPeople || showChannels) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Посты',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
      }
      for (final post in _posts) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NewPostCard(
              post: post,
              onPostDeleted: () {
                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                });
              },
              onAuthorTap: () {
                context.push(ProfileRoute.withUserId(post.userId));
              },
            ),
          ),
        );
      }
      if (_isLoading) {
        children.add(
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }
    }

    if (showMessages) {
      if (showPeople || showChannels || showPosts) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Сообщения',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
      }
      for (final item in _messageHits) {
        children.add(_buildMessageHitTile(item, query));
      }
    }

    return RefreshIndicator(
      onRefresh: () => _performSearch(),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

  Widget _buildPersonTile(ChatUserSearchItem user, String query) {
    final brief = user.brief;
    final avatarUrl = brief.avatarUrl;
    final resolved = avatarUrl != null && avatarUrl.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(avatarUrl)
        : null;
    final displayName = brief.displayName;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: resolved != null
            ? ResizeImage(CachedNetworkImageProvider(resolved), width: 96)
            : null,
        child: resolved == null
            ? Text(
                displayName.isNotEmpty
                    ? displayName.characters.first.toUpperCase()
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: HighlightedText(
        text: displayName,
        query: query,
        style: Theme.of(context).textTheme.bodyLarge!,
      ),
      subtitle: user.username != null
          ? HighlightedText(
              text: '@${user.username}',
              query: query,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : null,
      trailing: IconButton(
        tooltip: 'Написать',
        icon: const Icon(Icons.chat_bubble_outline),
        onPressed: () => _openPersonChat(user),
      ),
      onTap: () => context.push(ProfileRoute.withUserId(user.id)),
    );
  }

  Widget _buildChannelTile(Channel channel, String query) {
    final avatarUrl = channel.avatarUrl;
    final resolved = avatarUrl != null && avatarUrl.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(avatarUrl)
        : null;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: resolved != null
            ? ResizeImage(CachedNetworkImageProvider(resolved), width: 96)
            : null,
        child: resolved == null
            ? Text(
                channel.name.isNotEmpty
                    ? channel.name.characters.first.toUpperCase()
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: HighlightedText(
        text: channel.name,
        query: query,
        style: Theme.of(context).textTheme.bodyLarge!,
      ),
      subtitle: channel.description != null && channel.description!.isNotEmpty
          ? HighlightedText(
              text: channel.description!,
              query: query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Text('${channel.membersCount} подписчиков'),
      onTap: () => context.push(ChannelDetailRoute.pathFor(channel.id)),
    );
  }

  Widget _buildMessageHitTile(ChatMessageSearchItem hit, String query) {
    final convTitle = hit.conversation.displayTitle;
    final snippet =
        hit.snippet.trim().isEmpty ? hit.message.content : hit.snippet;
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.forum_outlined, size: 18),
      ),
      title: HighlightedText(
        text: convTitle,
        query: query,
        style: Theme.of(context).textTheme.bodyLarge!,
      ),
      subtitle: HighlightedText(
        text: snippet,
        query: query,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: Text(
        hit.message.type.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      onTap: () {
        unawaited(ChatThreadPrefetch.warm(hit.conversation.id));
        context.push(
          ChatThreadRoute.pathFor(hit.conversation),
          extra: ChatThreadOpenArgs(
            conversation: hit.conversation,
            jumpToMessageId: hit.message.id,
          ),
        );
      },
    );
  }

  Widget _buildMessageTypeChip(String? value, String label) {
    final selected = _selectedMessageType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedMessageType = value);
          if (_searchController.text.trim().isNotEmpty) {
            _performSearch();
          }
        },
      ),
    );
  }
}
