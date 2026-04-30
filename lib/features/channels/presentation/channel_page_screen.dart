// Страница канала
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';
import '../../../models/post_model.dart';
import '../../../services/user_posts_service.dart';
import '../../feed/presentation/new_post_card.dart';

class ChannelPageScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelPageScreen({
    Key? key,
    required this.channelId,
  }) : super(key: key);

  @override
  ConsumerState<ChannelPageScreen> createState() => _ChannelPageScreenState();
}

class _ChannelPageScreenState extends ConsumerState<ChannelPageScreen> {
  ChannelDetail? _channel;
  bool _isLoading = true;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    setState(() => _isLoading = true);

    try {
      final channel = await ChannelService.getChannel(widget.channelId);
      setState(() => _channel = channel);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки канала: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleJoin() async {
    if (_channel == null || _isJoining) return;

    setState(() => _isJoining = true);

    try {
      final response = _channel!.isMember
          ? await ChannelService.leaveChannel(widget.channelId)
          : await ChannelService.joinChannel(widget.channelId);

      setState(() {
        _channel = ChannelDetail(
          id: _channel!.id,
          name: _channel!.name,
          slug: _channel!.slug,
          description: _channel!.description,
          coverUrl: _channel!.coverUrl,
          avatarUrl: _channel!.avatarUrl,
          adminUserId: _channel!.adminUserId,
          isPublic: _channel!.isPublic,
          membersCount: response.membersCount,
          postsCount: _channel!.postsCount,
          createdAt: _channel!.createdAt,
          adminUser: _channel!.adminUser,
          isMember: response.joined,
          isAdmin: _channel!.isAdmin,
          isOwner: _channel!.isOwner,
          isModerator: _channel!.isModerator,
          tags: _channel!.tags,
          rules: _channel!.rules,
          autoPublishToFeed: _channel!.autoPublishToFeed,
          autoPublishToMenu: _channel!.autoPublishToMenu,
          autoPublishReels: _channel!.autoPublishReels,
          allowComments: _channel!.allowComments,
          allowLikes: _channel!.allowLikes,
          allowReposts: _channel!.allowReposts,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_channel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const Center(child: Text('Канал не найден')),
      );
    }

    return Scaffold(
      floatingActionButton: _channel!.isAdmin || _channel!.isMember
          ? FloatingActionButton(
              onPressed: () {
                _showCreateContentMenu(context);
              },
              child: const Icon(Icons.add),
              tooltip: 'Создать контент',
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: _channel!.coverUrl != null
                    ? Image.network(
                        _channel!.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholderCover(),
                      )
                    : _buildPlaceholderCover(),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildChannelHeader(),
            ),
          ];
        },
        body: _ChannelPostsTab(channelId: widget.channelId),
      ),
    );
  }

  Widget _buildChannelHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Аватар
          CircleAvatar(
            radius: 40,
            backgroundImage: _channel!.avatarUrl != null
                ? NetworkImage(_channel!.avatarUrl!)
                : null,
            child: _channel!.avatarUrl == null
                ? Text(
                    _channel!.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 40),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          // Название
          Text(
            _channel!.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_channel!.description != null &&
              _channel!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _channel!.description!,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          // Статистика
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              InkWell(
                onTap: () {
                  // Показываем участников
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => DraggableScrollableSheet(
                      initialChildSize: 0.7,
                      minChildSize: 0.5,
                      maxChildSize: 0.95,
                      builder: (context, scrollController) =>
                          _ChannelMembersTab(
                        channelId: widget.channelId,
                        scrollController: scrollController,
                      ),
                    ),
                  );
                },
                child: _StatItem(
                    label: 'Участники', value: '${_channel!.membersCount}'),
              ),
              _StatItem(label: 'Посты', value: '${_channel!.postsCount}'),
            ],
          ),
          const SizedBox(height: 16),
          // Кнопки действий
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_channel!.isAdmin)
                OutlinedButton.icon(
                  onPressed: () {
                    context.push(
                        '/channel/${widget.channelId}/settings?channelName=${Uri.encodeComponent(_channel!.name)}');
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Настройки'),
                ),
              if (_channel!.isAdmin) const SizedBox(width: 8),
              FilledButton(
                onPressed: _isJoining ? null : _toggleJoin,
                child: Text(
                    _channel!.isMember ? 'Покинуть канал' : 'Присоединиться'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderCover() {
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
    );
  }

  void _showCreateContentMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('Создать рецепт'),
              subtitle: const Text('Рецепт появится в Menu и в канале'),
              onTap: () {
                Navigator.of(context).pop();
                context
                    .push(
                  '/channel/${widget.channelId}/create-recipe?channelName=${Uri.encodeComponent(_channel!.name)}',
                )
                    .then((success) {
                  if (success == true) {
                    // Обновляем посты после публикации
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Пост с фото'),
              subtitle: const Text('Текст и изображения'),
              onTap: () {
                Navigator.of(context).pop();
                context
                    .push(
                  '/channel/${widget.channelId}/create-post?channelName=${Uri.encodeComponent(_channel!.name)}&type=photo',
                )
                    .then((success) {
                  if (success == true) {
                    // Обновляем посты после публикации
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Текстовый пост'),
              subtitle: const Text('Только текст'),
              onTap: () {
                Navigator.of(context).pop();
                context
                    .push(
                  '/channel/${widget.channelId}/create-post?channelName=${Uri.encodeComponent(_channel!.name)}&type=text',
                )
                    .then((success) {
                  if (success == true) {
                    // Обновляем посты после публикации
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Рилс (короткое видео)'),
              subtitle: const Text('Автоматически в раздел Рилсы'),
              onTap: () {
                Navigator.of(context).pop();
                context
                    .push(
                  '/channel/${widget.channelId}/create-post?channelName=${Uri.encodeComponent(_channel!.name)}&type=reel',
                )
                    .then((success) {
                  if (success == true) {
                    // Обновляем посты после публикации
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _ChannelPostsTab extends StatefulWidget {
  final int channelId;

  const _ChannelPostsTab({required this.channelId});

  @override
  State<_ChannelPostsTab> createState() => _ChannelPostsTabState();
}

class _ChannelPostsTabState extends State<_ChannelPostsTab> {
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMore = true;
      }
    });

    try {
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 20,
        offset: refresh ? 0 : _offset,
      );

      final posts = response.posts.map((p) => PostModel.fromJson(p)).toList();

      setState(() {
        if (refresh) {
          _posts = posts;
        } else {
          _posts.addAll(posts);
        }
        _offset = _posts.length;
        _hasMore = _posts.length < response.total;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки постов: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadPosts(refresh: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return const Center(child: Text('Нет постов'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_hasMore ? 1 : 0),
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
          return NewPostCard(
            post: post,
            onCommentTap: () {
              context.push('/post/${post.id}/comments');
            },
            onAuthorTap: () {
              context.push('/profile?userId=${post.userId}');
            },
          );
        },
      ),
    );
  }
}

class _ChannelMembersTab extends StatefulWidget {
  final int channelId;
  final ScrollController? scrollController;

  const _ChannelMembersTab({
    required this.channelId,
    this.scrollController,
  });

  @override
  State<_ChannelMembersTab> createState() => _ChannelMembersTabState();
}

class _ChannelMembersTabState extends State<_ChannelMembersTab> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final data = await ChannelService.getChannelMembers(
        channelId: widget.channelId,
        limit: 50,
      );
      setState(() {
        _members = (data['members'] as List<dynamic>?)
                ?.map((m) => m as Map<String, dynamic>)
                .toList() ??
            [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки участников: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Участники',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text('${_members.length}'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _members.isEmpty
                  ? const Center(child: Text('Нет участников'))
                  : ListView(
                      controller: widget.scrollController,
                      children: _members.map((member) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: member['avatar_url'] != null
                                ? NetworkImage(member['avatar_url'] as String)
                                : null,
                            child: member['avatar_url'] == null
                                ? Text((member['name'] as String? ??
                                        member['username'] as String? ??
                                        'U')[0]
                                    .toUpperCase())
                                : null,
                          ),
                          title: Text(member['name'] as String? ??
                              member['username'] as String? ??
                              'Пользователь'),
                          subtitle: Text(member['username'] as String? ?? ''),
                          trailing: member['role'] == 'admin'
                              ? Chip(
                                  label: const Text('Админ'),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                )
                              : member['role'] == 'moderator'
                                  ? Chip(
                                      label: const Text('Модератор'),
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                    )
                                  : null,
                          onTap: () {
                            context
                                .push('/profile?userId=${member['user_id']}');
                            Navigator.of(context).pop();
                          },
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}
