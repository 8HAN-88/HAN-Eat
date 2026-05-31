// Главный экран раздела "Каналы" согласно ТЗ
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/channel_list_badges.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../application/channels_list_refresh_provider.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/app_empty_state.dart';

class ChannelsMainScreen extends ConsumerStatefulWidget {
  const ChannelsMainScreen({super.key});

  @override
  ConsumerState<ChannelsMainScreen> createState() => _ChannelsMainScreenState();
}

class _ChannelsMainScreenState extends ConsumerState<ChannelsMainScreen> {
  List<Channel> _ownedChannels = [];
  List<Channel> _subscribedChannels = [];
  List<Channel> _recommendedChannels = [];
  bool _isLoadingOwned = false;
  bool _isLoadingSubscribed = false;
  bool _isLoadingRecommended = false;
  bool _channelsReloadLocked = false;
  Object? _listLoadError;
  final ScrollController _scrollController = ScrollController();

  List<Channel> _uniqueById(Iterable<Channel> channels) {
    final seen = <int>{};
    final out = <Channel>[];
    for (final c in channels) {
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }

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
    if (_channelsReloadLocked) return;
    _channelsReloadLocked = true;

    setState(() {
      if (refresh) {
        _ownedChannels = [];
        _subscribedChannels = [];
        _recommendedChannels = [];
        _listLoadError = null;
      }
      _isLoadingOwned = true;
      _isLoadingSubscribed = true;
      _isLoadingRecommended = true;
    });

    try {
      await _loadOwnedChannels();
      await Future.wait([
        _loadSubscribedChannels(),
        _loadRecommendedChannels(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _channelsReloadLocked = false);
      }
    }
  }

  Future<void> _loadOwnedChannels() async {
    try {
      final response = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        mine: true,
      );
      if (mounted) {
        setState(() {
          _ownedChannels = _uniqueById(response.items);
          _isLoadingOwned = false;
          _listLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOwned = false;
          _listLoadError = e;
        });
      }
    }
  }

  Future<void> _loadSubscribedChannels() async {
    try {
      final response = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        subscribed: true,
      );
      final ownedIds = _ownedChannels.map((c) => c.id).toSet();

      if (mounted) {
        setState(() {
          _subscribedChannels = _uniqueById(
            response.items.where((c) => !ownedIds.contains(c.id)),
          );
          _isLoadingSubscribed = false;
          _listLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSubscribed = false;
          if (_ownedChannels.isEmpty) {
            _listLoadError = e;
          }
        });
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
      final excludedIds = {
        ..._ownedChannels.map((c) => c.id),
        ..._subscribedChannels.map((c) => c.id),
      };

      if (mounted) {
        setState(() {
          _recommendedChannels = _uniqueById(
            response.items.where((c) => !excludedIds.contains(c.id)),
          );
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
    ref.listen<int>(channelsMainListRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadChannels(refresh: true);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Создать канал',
            onPressed: () {
              context.push(CreateChannelRoute.path).then((channelId) {
                if (channelId != null && channelId is int) {
                  _loadChannels(refresh: true);
                  context.push(ChannelDetailRoute.pathFor(channelId));
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              context.push(ChannelsManagementRoute.path);
            },
            tooltip: 'Управление каналами',
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: AppGradientBackground(
        child: (_isLoadingOwned && _ownedChannels.isEmpty) &&
              (_isLoadingSubscribed && _subscribedChannels.isEmpty) &&
              (_isLoadingRecommended && _recommendedChannels.isEmpty)
          ? RefreshIndicator(
              onRefresh: () => _loadChannels(refresh: true),
              child: _buildSkeletonScrollable(),
            )
          : _ownedChannels.isEmpty &&
              _subscribedChannels.isEmpty &&
              _recommendedChannels.isEmpty
              ? RefreshIndicator(
                  onRefresh: () => _loadChannels(refresh: true),
                  child: _listLoadError != null
                      ? _buildLoadErrorScrollable()
                      : _buildEmptyStateScrollable(),
                )
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
                              final q = value.trim();
                              if (q.isNotEmpty) {
                                context.push(
                                    ChannelsManagementRoute.pathWithSearch(q));
                              }
                            },
                          ),
                        ),
                      ),
                      if (_ownedChannels.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Text(
                              'Мои каналы:',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _ChannelCard(
                                channel: _ownedChannels[index],
                                onTap: () {
                                  context.push(ChannelDetailRoute.pathFor(
                                      _ownedChannels[index].id));
                                },
                              );
                            },
                            childCount: _ownedChannels.length,
                          ),
                        ),
                      ],
                      if (_subscribedChannels.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Text(
                              'Подписки:',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
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
                                  context.push(ChannelDetailRoute.pathFor(
                                      _subscribedChannels[index].id));
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
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
                                  context.push(ChannelDetailRoute.pathFor(
                                      _recommendedChannels[index].id));
                                },
                              );
                            },
                            childCount: _recommendedChannels.length,
                          ),
                        ),
                      ],
                      SliverPadding(
                        padding: EdgeInsets.only(
                          bottom: floatingBottomPadding(context),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildSkeletonScrollable() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + floatingBottomPadding(context),
      ),
      children: List.generate(5, (_) => _SkeletonChannelCard()),
    );
  }

  Widget _buildLoadErrorScrollable() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить',
            subtitle: userVisibleError(
              _listLoadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: () => _loadChannels(refresh: true),
              child: const Text('Повторить'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateScrollable() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                32, 32, 32, 32 + floatingBottomPadding(context)),
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
                  'Нажмите «+» вверху справа, чтобы создать канал '
                  'или откройте каталог и подпишитесь.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    context.push(ChannelsManagementRoute.path);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Каталог каналов'),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _ChannelCardState extends State<_ChannelCard> {
  String? _lastPostPreview;
  DateTime? _lastPostAt;
  bool _isLoadingLastPost = false;
  int _seenPostsCount = 0;

  String get _seenPostsKey => 'channel_seen_posts_count_${widget.channel.id}';

  int get _newPostsCount {
    final delta = widget.channel.postsCount - _seenPostsCount;
    return delta > 0 ? delta : 0;
  }

  @override
  void initState() {
    super.initState();
    _loadSeenPostsCount();
    _loadLastPost();
  }

  Future<void> _loadSeenPostsCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_seenPostsKey) ?? 0;
      if (!mounted) return;
      setState(() => _seenPostsCount = seen);
    } catch (_) {
      // Безопасно игнорируем: UI просто не покажет бейдж "новых".
    }
  }

  Future<void> _markAsSeen() async {
    final latestCount = widget.channel.postsCount;
    if (latestCount <= _seenPostsCount) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenPostsKey, latestCount);
      if (!mounted) return;
      setState(() => _seenPostsCount = latestCount);
    } catch (_) {
      // Игнорируем ошибки локального кэша.
    }
  }

  String _membersLabel(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$n подписчиков';
    if (mod10 == 1) return '$n подписчик';
    if (mod10 >= 2 && mod10 <= 4) return '$n подписчика';
    return '$n подписчиков';
  }

  String _subtitleLine() {
    if (widget.channel.postsCount > 0 && _isLoadingLastPost) {
      return 'Загрузка…';
    }
    if (widget.channel.postsCount > 0 && _lastPostPreview != null) {
      return _lastPostPreview!;
    }
    final d = widget.channel.description;
    if (d != null && d.trim().isNotEmpty) {
      return d.trim();
    }
    return _membersLabel(widget.channel.membersCount);
  }

  Future<void> _loadLastPost() async {
    if (_isLoadingLastPost) return;
    if (!widget.channel.canLoadPostsPreview) return;

    setState(() => _isLoadingLastPost = true);

    try {
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channel.id,
        limit: 1,
        offset: 0,
      );

      if (response.posts.isNotEmpty) {
        final lastPost = response.posts.first;
        setState(() {
          _lastPostPreview = _buildPostPreview(lastPost);
          _lastPostAt = _parsePostDate(lastPost['created_at']);
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

  String _buildPostPreview(Map<String, dynamic> post) {
    final type = (post['type'] as String?)?.toLowerCase() ?? '';

    final title = (post['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;

    final description = (post['description'] as String?)?.trim();
    if (description != null && description.isNotEmpty) return description;

    if (type == 'recipe') {
      final body = post['body'];
      if (body is Map<String, dynamic>) {
        final steps = body['steps'];
        if (steps is List && steps.isNotEmpty) {
          final first = steps.first;
          if (first is Map<String, dynamic>) {
            final stepText = (first['text'] as String?)?.trim();
            if (stepText != null && stepText.isNotEmpty) return stepText;
          }
        }
        final ingredients = body['ingredients'];
        if (ingredients is List && ingredients.isNotEmpty) {
          final firstIngredient = ingredients.first?.toString().trim();
          if (firstIngredient != null && firstIngredient.isNotEmpty) {
            return firstIngredient;
          }
        }
      }
      return 'Рецепт';
    }

    if (type == 'reel' || type == 'video') return 'Видео';
    if (type == 'photo' || type == 'image') return 'Фотография';

    final media = post['media'];
    if (media is List) {
      for (final item in media) {
        if (item is! Map<String, dynamic>) continue;
        final mediaType = (item['type'] as String?)?.toLowerCase() ?? '';
        if (mediaType == 'video' || mediaType == 'reel') return 'Видео';
        if (mediaType == 'image' || mediaType == 'photo') return 'Фотография';
      }
    }

    return 'Новый пост';
  }

  DateTime? _parsePostDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String? _formatPostTime(DateTime? dt) {
    if (dt == null) return null;
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd.$mo';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: InkWell(
        onTap: () async {
          await _markAsSeen();
          widget.onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: widget.channel.avatarUrl != null
                        ? CachedNetworkImageProvider(widget.channel.avatarUrl!)
                        : null,
                    child: widget.channel.avatarUrl == null
                        ? Text(
                            widget.channel.name.isNotEmpty
                                ? widget.channel.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.channel.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_formatPostTime(_lastPostAt) != null)
                              Text(
                                _formatPostTime(_lastPostAt)!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            if (_newPostsCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _newPostsCount > 99
                                      ? '99+'
                                      : '$_newPostsCount',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitleLine(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        ChannelListBadges(channel: widget.channel, spacing: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: 12 + 52 + 12,
              color: theme.dividerColor.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonChannelCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = Colors.grey[300];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: base,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 12,
                  decoration: BoxDecoration(
                    color: base,
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
