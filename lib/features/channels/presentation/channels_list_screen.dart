// Список каналов
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';
import 'channel_page_screen.dart';
import 'create_channel_screen.dart';

class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen> 
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _channels = [];
  bool _isLoading = false;
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
    setState(() {
      if (_tabController.index == 3) {
        // Вкладка "Создать канал"
        context.push(CreateChannelRoute.path).then((channelId) {
          if (channelId != null && mounted) {
            context.push('/channel/$channelId');
          }
          // Возвращаемся на первую вкладку
          if (mounted) {
            _tabController.animateTo(0);
          }
        });
      } else {
        _loadChannels(refresh: true);
      }
    });
  }
  
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }
  
  Future<void> _loadChannels({bool refresh = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _channels = [];
        _offset = 0;
        _hasMore = true;
      }
    });
    
    try {
      // Определяем тип загрузки в зависимости от выбранной вкладки
      final tabIndex = _tabController.index;
      final response = await ChannelService.listChannels(
        limit: 20,
        offset: refresh ? 0 : _offset,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        subscribed: tabIndex == 0, // Мои каналы
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
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки каналов: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
      child: TabBar(
        controller: _tabController,
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
      // Вкладка "Создать канал" - показываем пустой экран, так как навигация уже выполнена
      return const Center(child: Text('Создание канала...'));
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
                        _loadChannels(refresh: true);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onSubmitted: (_) => _loadChannels(refresh: true),
          ),
        ),
        // Список каналов
        Expanded(
          child: _channels.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _channels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Нет каналов',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              context.push(CreateChannelRoute.path);
                            },
                            child: const Text('Создать первый канал'),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          context.push('/channel/${channel.id}');
        },
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
                    if (channel.description != null && channel.description!.isNotEmpty) ...[
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
                        Icon(Icons.people_outline, size: 16, color: Colors.grey[600]),
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
    );
  }
}

class CreateChannelRoute {
  static const path = '/create-channel';
  static const name = 'create_channel';
}

