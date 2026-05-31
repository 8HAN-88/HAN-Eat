import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../app/app_router.dart';
import '../../../models/community_video.dart';
import '../../../widgets/report_content_dialog.dart';
import '../application/community_controller.dart';
import '../application/community_search_controller.dart';
import 'community_upload_screen.dart';
import '../../feed/presentation/feed_screen.dart';
import '../../feed/presentation/subscriptions_feed_screen.dart';
import '../../reels/presentation/reels_feed_screen.dart' as api_reels;
import '../../../core/layout/long_label_tab_bar.dart';
import '../../../widgets/app_empty_state.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    // Начинаем с таба «Рилсы» для лучшего удержания пользователя
    _tabController = TabController(length: 4, vsync: this, initialIndex: 3);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityControllerProvider);
    final controller = ref.read(communityControllerProvider.notifier);
    final searchState = ref.watch(communitySearchControllerProvider);
    final searchController = ref.read(communitySearchControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: _isSearchMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearchMode = false;
                    _searchController.clear();
                    searchController.clearSearch();
                  });
                },
              )
            : null,
        title: _isSearchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Поиск...',
                  border: InputBorder.none,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            searchController.clearSearch();
                            setState(() {});
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          if (_searchController.text.trim().isNotEmpty) {
                            searchController.search(_searchController.text.trim());
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                  if (value.trim().isEmpty) {
                    searchController.clearSearch();
                  }
                },
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    searchController.search(value.trim());
                  }
                },
              )
            : Row(
                children: [
                  Expanded(
                    child: longLabelTabBar(
                      controller: _tabController,
                      tabAlignment: TabAlignment.start,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      tabs: const [
                        Tab(text: 'Подписки'),
                        Tab(text: 'Лента'),
                        Tab(text: 'Видео'),
                        Tab(text: 'Рилсы'),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_outlined),
                    tooltip: 'Инструменты автора',
                    onPressed: () => context.push(CreatorToolsRoute.path),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      setState(() {
                        _isSearchMode = true;
                      });
                    },
                  ),
                ],
              ),
        elevation: 0,
      ),
      body: _isSearchMode
          ? _buildSearchView(context, searchState, searchController)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSubscriptionsTab(context),
                const FeedScreen(hideScaffold: true),
                _buildRecommendationsTab(context, state, controller),
                const api_reels.ReelsFeedScreen(),
              ],
            ),
      floatingActionButton: _isSearchMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const CommunityUploadScreen(),
                  ),
                );
                if (created == true) {
                  controller.load(tag: state.activeTag);
                }
              },
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Загрузить'),
            ),
    );
  }

  Widget _buildSearchView(
    BuildContext context,
    CommunitySearchState searchState,
    CommunitySearchController searchController,
  ) {
    return Column(
      children: [
        // Типы поиска (Лучшее, Автор, Видео)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<SearchType>(
                  segments: const [
                    ButtonSegment(
                      value: SearchType.best,
                      label: Text('Лучшее'),
                    ),
                    ButtonSegment(
                      value: SearchType.author,
                      label: Text('Автор'),
                    ),
                    ButtonSegment(
                      value: SearchType.video,
                      label: Text('Видео'),
                    ),
                    ButtonSegment(
                      value: SearchType.hashtag,
                      label: Text('Хештеги'),
                    ),
                    ButtonSegment(
                      value: SearchType.category,
                      label: Text('Категории'),
                    ),
                  ],
                  selected: {searchState.searchType},
                  onSelectionChanged: (selection) {
                    searchController.setSearchType(selection.first);
                  },
                ),
              ),
            ],
          ),
        ),
        // Фильтры
        if (searchState.searchQuery.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _SearchFilters(
              onFilterChanged: (filters) {
                searchController.setFilters(filters);
              },
            ),
          ),
        // Результаты поиска
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (searchState.searchQuery.isNotEmpty) {
                searchController.search(searchState.searchQuery);
              }
            },
            child: searchState.loading
                ? const Center(child: CircularProgressIndicator())
                : searchState.error != null
                    ? AppEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Ошибка поиска',
                        subtitle: searchState.error,
                        action: OutlinedButton(
                          onPressed: () {
                            if (searchState.searchQuery.isNotEmpty) {
                              searchController.search(searchState.searchQuery);
                            }
                          },
                          child: const Text('Повторить'),
                        ),
                      )
                    : searchState.videos.isEmpty
                        ? AppEmptyState(
                            icon: searchState.searchQuery.isEmpty
                                ? Icons.search_rounded
                                : Icons.video_library_outlined,
                            title: searchState.searchQuery.isEmpty
                                ? 'Поиск по видео'
                                : 'Ничего не найдено',
                            subtitle: searchState.searchQuery.isEmpty
                                ? 'Введите запрос в строке выше'
                                : 'Попробуйте другие слова или фильтр',
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: searchState.videos.map(
                              (video) => Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: _CommunityVideoCard(
                                  video: video,
                                  onLike: () {
                                    // Лайк через основной контроллер
                                    ref.read(communityControllerProvider.notifier).like(video.id);
                                  },
                                ),
                              ),
                            ).toList(),
                          ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsTab(
    BuildContext context,
    CommunityState state,
    CommunityController controller,
  ) {
    return RefreshIndicator(
      onRefresh: () => controller.load(tag: state.activeTag),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _CommunityFilters(
            activeTag: state.activeTag,
            onSelected: (tag) => controller.load(tag: tag == 'all' ? null : tag),
          ),
          if (state.loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Загружаем видео...'),
                ],
              ),
            )
          else if (state.error != null && state.error!.isNotEmpty)
            AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Не удалось загрузить',
              subtitle: state.error,
              action: OutlinedButton(
                onPressed: () => controller.load(tag: state.activeTag),
                child: const Text('Повторить'),
              ),
            )
          else if (state.videos.isEmpty)
            const AppEmptyState(
              icon: Icons.video_library_outlined,
              title: 'Пока нет видео',
              subtitle: 'Смените фильтр или загрузите своё видео',
            )
          else
            ...state.videos.map(
              (video) => Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _CommunityVideoCard(
                  video: video,
                  onLike: () => controller.like(video.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsTab(BuildContext context) {
    return const SubscriptionsFeedScreen();
  }
}

class _SearchFilters extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onFilterChanged;

  const _SearchFilters({required this.onFilterChanged});

  @override
  State<_SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<_SearchFilters> {
  final Map<String, dynamic> _filters = {};
  final List<String> _availableTags = ['боул', 'здоровье', 'рыба', 'comfort', 'веган'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('По тегу'),
          selected: _filters.containsKey('tag'),
          onSelected: (selected) {
            if (selected) {
              _showTagPicker();
            } else {
              setState(() {
                _filters.remove('tag');
              });
              widget.onFilterChanged(Map.from(_filters));
            }
          },
        ),
        if (_filters.containsKey('tag'))
          Chip(
            label: Text(_filters['tag'] as String),
            onDeleted: () {
              setState(() {
                _filters.remove('tag');
              });
              widget.onFilterChanged(Map.from(_filters));
            },
          ),
        ChoiceChip(
          label: const Text('Минимум лайков'),
          selected: _filters.containsKey('minLikes'),
          onSelected: (selected) {
            if (selected) {
              _showLikesPicker();
            } else {
              setState(() {
                _filters.remove('minLikes');
              });
              widget.onFilterChanged(Map.from(_filters));
            }
          },
        ),
        if (_filters.containsKey('minLikes'))
          Chip(
            label: Text('${_filters['minLikes']}+ лайков'),
            onDeleted: () {
              setState(() {
                _filters.remove('minLikes');
              });
              widget.onFilterChanged(Map.from(_filters));
            },
          ),
      ],
    );
  }

  void _showTagPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите тег'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _availableTags.map((tag) {
            return ListTile(
              title: Text(tag),
              onTap: () {
                setState(() {
                  _filters['tag'] = tag;
                });
                widget.onFilterChanged(Map.from(_filters));
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLikesPicker() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Минимум лайков'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Введите число',
            labelText: 'Лайков',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final likes = int.tryParse(controller.text);
              if (likes != null && likes > 0) {
                setState(() {
                  _filters['minLikes'] = likes;
                });
                widget.onFilterChanged(Map.from(_filters));
                Navigator.of(context).pop();
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }
}

class _CommunityFilters extends StatelessWidget {
  const _CommunityFilters({
    required this.activeTag,
    required this.onSelected,
  });

  final String? activeTag;
  final ValueChanged<String> onSelected;

  static const filters = [
    {'label': 'Все', 'value': 'all'},
    {'label': 'Боулы', 'value': 'боул'},
    {'label': 'ЗОЖ', 'value': 'здоровье'},
    {'label': 'Рыба', 'value': 'рыба'},
    {'label': 'Comfort', 'value': 'comfort'},
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter['label']!),
            selected: activeTag == filter['value'] ||
                (filter['value'] == 'all' && (activeTag == null || activeTag!.isEmpty)),
            onSelected: (_) => onSelected(filter['value']!),
          ),
      ],
    );
  }
}

class _CommunityVideoCard extends StatefulWidget {
  const _CommunityVideoCard({
    required this.video,
    required this.onLike,
  });

  final CommunityVideo video;
  final VoidCallback onLike;

  @override
  State<_CommunityVideoCard> createState() => _CommunityVideoCardState();
}

class _CommunityVideoCardState extends State<_CommunityVideoCard> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _initializing = true;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.video.videoUrl),
    );
    _videoController.initialize().then((_) {
      if (!mounted) return;
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: false,
        looping: true,
        allowFullScreen: true,
        showControls: false, // Скрываем стандартные контролы для тапа на видео
        allowMuting: false, // Отключаем звук
        allowPlaybackSpeedChanging: false,
      );
      setState(() {
        _initializing = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _initializing = false);
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Initialize date format with error handling
    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('d MMM, HH:mm', 'ru');
    } catch (e) {
      // Fallback to default locale if Russian is not initialized
      dateFormat = DateFormat('d MMM, HH:mm');
    }
    final likes = widget.video.likes;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_initializing)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_chewieController != null)
            AspectRatio(
              aspectRatio: _videoController.value.aspectRatio == 0
                  ? 16 / 9
                  : _videoController.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isPaused = !_isPaused;
                      });
                      if (_isPaused) {
                        _chewieController!.pause();
                      } else {
                        _chewieController!.play();
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Chewie(controller: _chewieController!),
                  ),
                  // Индикатор паузы
                  if (_isPaused)
                    IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                        child: const Center(
                          child: Icon(
                            Icons.pause_circle_filled,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.error_outline)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: widget.video.avatar != null
                          ? NetworkImage(widget.video.avatar!)
                          : null,
                      child: widget.video.avatar == null
                          ? const Icon(Icons.person_outline)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.video.author,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            dateFormat.format(widget.video.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'report' && widget.video.id > 0) {
                          reportPostWithDialog(context, widget.video.id);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'report',
                          child: ListTile(
                            leading: Icon(Icons.flag_outlined),
                            title: Text('Пожаловаться'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onLike,
                      icon: const Icon(Icons.favorite_border),
                      tooltip: 'Нравится',
                    ),
                    Text('$likes'),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: widget.video.id > 0
                          ? () => context.push(
                                PostCommentsRoute.pathFor(widget.video.id),
                              )
                          : null,
                      icon: const Icon(Icons.chat_bubble_outline),
                      tooltip: 'Комментарии',
                    ),
                    Text('${widget.video.commentsCount}'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.video.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!widget.video.isPublished)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Chip(
                      avatar: const Icon(Icons.shield_moon_outlined, size: 18),
                      label: const Text('На модерации'),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  widget.video.description,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: widget.video.tags
                      .map((tag) => Chip(label: Text('#$tag')))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
