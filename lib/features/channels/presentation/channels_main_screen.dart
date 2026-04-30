// Главный экран раздела "Каналы" согласно ТЗ
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../services/channel_service.dart';
import 'channel_detail_screen.dart';
import 'channels_management_screen.dart';

class ChannelsMainScreen extends ConsumerStatefulWidget {
  const ChannelsMainScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<ChannelsMainScreen> createState() => _ChannelsMainScreenState();
}

class _ChannelsMainScreenState extends ConsumerState<ChannelsMainScreen> {
  List<Channel> _subscribedChannels = [];
  List<Channel> _recommendedChannels = [];
  bool _isLoadingSubscribed = false;
  bool _isLoadingRecommended = false;
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _loadChannels();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadChannels({bool refresh = false}) async {
    if (_isLoadingSubscribed && _isLoadingRecommended) return;
    
    setState(() {
      if (refresh) {
        _subscribedChannels = [];
        _recommendedChannels = [];
      }
      _isLoadingSubscribed = true;
      _isLoadingRecommended = true;
    });
    
    // Загружаем подписки и рекомендации параллельно
    await Future.wait([
      _loadSubscribedChannels(),
      _loadRecommendedChannels(),
    ]);
  }
  
  Future<void> _loadSubscribedChannels() async {
    try {
      final response = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        subscribed: true,
      );
      
      if (mounted) {
        setState(() {
          _subscribedChannels = response.items;
          _isLoadingSubscribed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSubscribed = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки подписок: $e')),
        );
      }
    }
  }
  
  Future<void> _loadRecommendedChannels() async {
    try {
      final response = await ChannelService.listChannels(
        limit: 10,
        offset: 0,
        recommended: true,
      );
      
      if (mounted) {
        setState(() {
          _recommendedChannels = response.items;
          _isLoadingRecommended = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRecommended = false);
        // Не показываем ошибку для рекомендаций, они не критичны
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              context.push('/channels/management');
            },
            tooltip: 'Управление каналами',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/create-channel').then((channelId) {
            if (channelId != null && channelId is int) {
              // Обновляем список каналов после создания
              _loadChannels(refresh: true);
              // Переходим на созданный канал
              context.push('/channel/$channelId');
            }
          });
        },
        child: const Icon(Icons.add),
        tooltip: 'Создать канал',
      ),
      body: (_isLoadingSubscribed && _subscribedChannels.isEmpty) && 
            (_isLoadingRecommended && _recommendedChannels.isEmpty)
          ? _buildSkeletonLoading()
          : _subscribedChannels.isEmpty && _recommendedChannels.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadChannels(refresh: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Поиск
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Поиск каналов',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                context.push('/channels/management?search=${Uri.encodeComponent(value.trim())}');
                              }
                            },
                          ),
                        ),
                      ),
                      // Подписки
                      if (_subscribedChannels.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              'Подписки:',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _ChannelCard(
                                channel: _subscribedChannels[index],
                                onTap: () {
                                  context.push('/channel/${_subscribedChannels[index].id}');
                                },
                              );
                            },
                            childCount: _subscribedChannels.length,
                          ),
                        ),
                      ],
                      // Рекомендации
                      if (_recommendedChannels.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'Для вас (рекомендации):',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _ChannelCard(
                                channel: _recommendedChannels[index],
                                onTap: () {
                                  context.push('/channel/${_recommendedChannels[index].id}');
                                },
                              );
                            },
                            childCount: _recommendedChannels.length,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
  
  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) {
        return _SkeletonChannelCard();
      },
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'Вы ещё не подписаны ни на один канал',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите «+» чтобы добавить первый канал',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                context.push('/channels/management');
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить канал'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  
  const _ChannelCard({
    required this.channel,
    required this.onTap,
  });
  
  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  String? _lastPostPreview;
  bool _isLoadingLastPost = false;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadLastPost();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _loadLastPost() async {
    if (_isLoadingLastPost) return;
    
    setState(() => _isLoadingLastPost = true);
    
    try {
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channel.id,
        limit: 1,
        offset: 0,
      );
      
      if (response.posts.isNotEmpty) {
        final lastPost = response.posts.first;
        final title = lastPost['title'] as String?;
        final description = lastPost['description'] as String?;
        
        setState(() {
          if (title != null && title.isNotEmpty) {
            _lastPostPreview = title;
          } else if (description != null && description.isNotEmpty) {
            _lastPostPreview = description;
          } else {
            _lastPostPreview = 'Новый пост';
          }
        });
      }
    } catch (e) {
      // Игнорируем ошибки
    } finally {
      if (mounted) {
        setState(() => _isLoadingLastPost = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) {
        _animationController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _animationController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Аватар канала
                CircleAvatar(
                  radius: 28,
                  backgroundImage: widget.channel.avatarUrl != null
                      ? CachedNetworkImageProvider(widget.channel.avatarUrl!)
                      : null,
                  child: widget.channel.avatarUrl == null
                      ? Text(
                          widget.channel.name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Информация о канале
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Название и количество постов
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.channel.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.channel.postsCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      // Описание
                      if (widget.channel.description != null && widget.channel.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.channel.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Последний пост
                      if (widget.channel.postsCount > 0) ...[
                        const SizedBox(height: 6),
                        _isLoadingLastPost
                            ? Text(
                                'Загрузка...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text(
                                _lastPostPreview != null
                                    ? 'Последний пост: $_lastPostPreview'
                                    : 'Нет постов',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonChannelCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 150,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


