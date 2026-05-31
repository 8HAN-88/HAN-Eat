// Страница канала
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';
import '../../../models/post_model.dart';
import '../../../app/app_router.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../../widgets/app_empty_state.dart';
class ChannelPageScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelPageScreen({
    super.key,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelPageScreen> createState() => _ChannelPageScreenState();
}

class _ChannelPageScreenState extends ConsumerState<ChannelPageScreen> {
  ChannelDetail? _channel;
  Object? _channelLoadError;
  bool _isLoading = true;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _channelLoadError = null;
    });

    try {
      final channel = await ChannelService.getChannel(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = channel;
          _channelLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _channelLoadError = e);
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
      final response = _channel!.isMember || _channel!.isPending
          ? await ChannelService.leaveChannel(widget.channelId)
          : await ChannelService.joinChannel(widget.channelId);

      await _loadChannel();
      if (response.pending && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Заявка отправлена. После одобрения модератора откроются посты канала.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
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
      if (_channelLoadError != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Канал')),
          body: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить канал',
            subtitle: userVisibleError(
              _channelLoadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: _loadChannel,
              child: const Text('Повторить'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const AppEmptyState(
          icon: Icons.group_off_outlined,
          title: 'Канал не найден',
          subtitle: 'Возможно, он удалён или у вас нет доступа',
        ),
      );
    }

    return Scaffold(
      floatingActionButton: _channel!.canViewPosts &&
              (_channel!.isAdmin ||
                  _channel!.isOwner ||
                  _channel!.isModerator ||
                  _channel!.isMember)
          ? FloatingActionButton(
              onPressed: () {
                _showCreateContentMenu(context);
              },
              tooltip: 'Создать контент',
              child: const Icon(Icons.add),
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
        body: _channel!.canViewPosts
            ? _ChannelPostsTab(channelId: widget.channelId)
            : _buildPostsLockedPlaceholder(),
      ),
    );
  }

  Widget _buildPostsLockedPlaceholder() {
    final c = _channel!;
    final message = c.isPending
        ? 'Заявка на вступление на рассмотрении. Посты появятся после одобрения.'
        : !c.isPublic
            ? 'Это приватный канал. Подпишитесь — модератор одобрит доступ к постам.'
            : 'Подпишитесь на канал, чтобы видеть публикации.';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            c.isPending ? Icons.hourglass_top : Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (c.isPending) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isJoining ? null : _toggleJoin,
              child: const Text('Отменить заявку'),
            ),
          ],
        ],
      ),
    );
  }

  String _joinButtonLabel(ChannelDetail c) {
    if (c.isMember) return 'Покинуть канал';
    if (c.isPending) return 'Ожидает одобрения';
    if (!c.isPublic) return 'Запросить вступление';
    return 'Присоединиться';
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
                onTap: _channel!.canViewPosts
                    ? () {
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
                }
                    : null,
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
                      ChannelDetailRoute.settings(
                        widget.channelId,
                        _channel!.name,
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Настройки'),
                ),
              if (_channel!.isAdmin) const SizedBox(width: 8),
              FilledButton(
                onPressed: (_isJoining || _channel!.isPending)
                    ? null
                    : _toggleJoin,
                child: Text(_joinButtonLabel(_channel!)),
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
              subtitle: const Text(
                'Выберите: публичный в Menu или приватный в канале',
              ),
              onTap: () async {
                Navigator.of(context).pop();
                if (!context.mounted) return;
                context
                    .push(
                  ChannelDetailRoute.createRecipe(
                    widget.channelId,
                    _channel!.name,
                  ),
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
                  ChannelDetailRoute.createPost(
                    widget.channelId,
                    channelName: _channel!.name,
                    type: 'photo',
                  ),
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
                  ChannelDetailRoute.createPost(
                    widget.channelId,
                    channelName: _channel!.name,
                    type: 'text',
                  ),
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
                  ChannelDetailRoute.createPost(
                    widget.channelId,
                    channelName: _channel!.name,
                    type: 'reel',
                  ),
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
  Object? _postsLoadError;
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
        _postsLoadError = null;
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
        _postsLoadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (refresh) {
            _postsLoadError = e;
          }
        });
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
      if (_postsLoadError != null) {
        return RefreshIndicator(
          onRefresh: () => _loadPosts(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.4,
                child: AppEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не удалось загрузить посты',
                  subtitle: userVisibleError(
                    _postsLoadError!,
                    fallback: 'Проверьте сеть',
                  ),
                  action: FilledButton(
                    onPressed: () => _loadPosts(refresh: true),
                    child: const Text('Повторить'),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            AppEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Здесь пока нет постов',
              subtitle: 'Как только появятся публикации — они будут здесь',
            ),
          ],
        ),
      );
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
            onCommentTap: () =>
                context.push(PostCommentsRoute.pathFor(post.id)),
            onAuthorTap: () {
              context.push(ProfileRoute.withUserId(post.userId));
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
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить участников'))),
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
                  ? const AppEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'Нет участников',
                      subtitle: 'Пригласите людей в канал',
                    )
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
                            final uid = member['user_id'];
                            final id = uid is int ? uid : int.tryParse('$uid');
                            if (id != null) {
                              context.push(ProfileRoute.withUserId(id));
                            }
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
