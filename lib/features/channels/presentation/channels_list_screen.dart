// Список каналов
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/channel_list_badges.dart';
import '../../../core/layout/long_label_tab_bar.dart';
import '../../../core/theme/app_card_decorations.dart';

class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({super.key});

  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _channels = [];
  Object? _loadError;
  bool _isLoading = false;
  bool _pendingLoadMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadChannels();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _tabController.animateTo(0);
        if (!mounted) return;
        final channelId = await context.push<Object?>(CreateChannelRoute.path);
        if (!mounted) return;
        if (channelId is int) {
          await _loadChannels(refresh: true);
          if (!mounted) return;
          context.push(ChannelDetailRoute.pathFor(channelId));
        }
      });
      return;
    }
    _loadChannels(refresh: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasViewportDimension || pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadChannels({bool refresh = false}) async {
    if (_isLoading) {
      if (!refresh) _pendingLoadMore = true;
      return;
    }

    setState(() {
      _isLoading = true;
      if (refresh) {
        _channels = [];
        _offset = 0;
        _hasMore = true;
        _loadError = null;
      }
    });

    try {
      final tabIndex = _tabController.index;
      if (tabIndex == 3) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await ChannelService.listChannels(
        limit: 20,
        offset: refresh ? 0 : _offset,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        mine: tabIndex == 0, // Каналы, где я создатель
        recommended: tabIndex == 1, // Рекомендованные
        catalog: tabIndex == 2, // Каталог
      );

      setState(() {
        if (refresh) {
          _channels = response.items;
        } else {
          _channels.addAll(response.items);
        }
        _offset = _channels.length;
        _hasMore = _channels.length < response.total;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    } finally {
      final stillMounted = mounted;
      if (stillMounted) {
        setState(() => _isLoading = false);
      }
      final runPending = _pendingLoadMore;
      _pendingLoadMore = false;
      if (runPending && _hasMore && stillMounted) {
        await _loadChannels(refresh: false);
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadChannels(refresh: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
      ),
      body: Column(
        children: [
          // Вкладки
          _buildTabs(),
          // Контент вкладок
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: longLabelTabBar(
        controller: _tabController,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        tabs: const [
          Tab(text: 'Мои каналы', icon: Icon(Icons.bookmark)),
          Tab(text: 'Рекомендованные', icon: Icon(Icons.explore)),
          Tab(text: 'Каталог', icon: Icon(Icons.list)),
          Tab(text: 'Создать', icon: Icon(Icons.add)),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    if (_tabController.index == 3) {
      return AppEmptyState(
        icon: Icons.add_circle_outline_rounded,
        title: 'Новый канал',
        subtitle: 'Создайте канал для рецептов и постов',
        action: FilledButton(
          onPressed: () => context.push(CreateChannelRoute.path),
          child: const Text('Создать канал'),
        ),
      );
    }

    return Column(
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск каналов...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        _loadChannels(refresh: true);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _loadChannels(refresh: true),
          ),
        ),
        // Список каналов
        Expanded(
          child: _channels.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _channels.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => _loadChannels(refresh: true),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _loadError != null
                                ? AppEmptyState(
                                    icon: Icons.cloud_off_rounded,
                                    title: 'Не удалось загрузить',
                                    subtitle: userVisibleError(
                                      _loadError!,
                                      fallback: 'Проверьте сеть',
                                    ),
                                    action: FilledButton(
                                      onPressed: () =>
                                          _loadChannels(refresh: true),
                                      child: const Text('Повторить'),
                                    ),
                                  )
                                : AppEmptyState(
                                    icon: Icons.group_outlined,
                                    title: 'Нет каналов',
                                    subtitle: _tabController.index == 0
                                        ? 'Создайте первый канал'
                                        : 'Попробуйте другой раздел или поиск',
                                    action: _tabController.index == 0
                                        ? FilledButton(
                                            onPressed: () => context.push(
                                              CreateChannelRoute.path,
                                            ),
                                            child: const Text('Создать канал'),
                                          )
                                        : null,
                                  ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadChannels(refresh: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _channels.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _channels.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final channel = _channels[index];
                          return _ChannelCard(channel: channel);
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final Channel channel;

  const _ChannelCard({required this.channel});

  @override
  Widget build(BuildContext context) {
    return AppElevatedCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: () {
          context.push(ChannelDetailRoute.pathFor(channel.id));
        },
        borderRadius: BorderRadius.circular(AppCardDecorations.defaultRadius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Аватар
              CircleAvatar(
                radius: 30,
                backgroundImage: channel.avatarUrl != null
                    ? NetworkImage(channel.avatarUrl!)
                    : null,
                child: channel.avatarUrl == null
                    ? Text(
                        channel.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 24),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ChannelListBadges(channel: channel),
                    if (channel.description != null &&
                        channel.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        channel.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${channel.membersCount} участников',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.post_add, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${channel.postsCount} постов',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
