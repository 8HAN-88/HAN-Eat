// Экран профиля пользователя
import 'dart:async';
import '../../../utils/api_error_parser.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/user_service.dart' as user_service;
import '../../../../services/user_posts_service.dart';
import '../../../../services/profile_cache_service.dart';
import '../../../../services/user_posts_cache_service.dart';
import '../../../../models/post_model.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../saved/presentation/saved_posts_screen.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/app_router.dart';
import '../../../../services/chat_service.dart';
import '../../../../widgets/app_avatar.dart';
import '../../navigation/application/shell_tab_visibility.dart';
import '../../../../core/layout/long_label_tab_bar.dart';
import '../../../../core/layout/floating_bottom_padding.dart';
import '../../../../widgets/app_empty_state.dart';
import '../../../../widgets/app_gradient_background.dart';
import '../../../../widgets/app_avatar_ring.dart';
import '../../../../core/theme/app_card_decorations.dart';
import '../../content/create_content_actions.dart';
import '../../../utils/post_publisher_display.dart';

/// Минимальный профиль из данных [AuthService], пока не пришёл ответ API.
user_service.UserProfile _userProfileFromAuthUser(User u) {
  return user_service.UserProfile(
    user: User(
      id: u.id,
      email: u.email,
      name: u.name,
      username: u.username,
      avatarUrl: u.avatarUrl,
      bio: u.bio,
      isPrivate: u.isPrivate,
      isAdmin: u.isAdmin,
      isModerator: u.isModerator,
      createdAt: u.createdAt,
      scanCredits: u.scanCredits,
      subscriptionType: u.subscriptionType,
    ),
    stats: user_service.UserStats(
      postsCount: 0,
      reelsCount: 0,
      savedCount: 0,
      followersCount: 0,
      followingCount: 0,
    ),
  );
}

class ProfileScreen extends ConsumerStatefulWidget {
  final int? userId; // Если null, показываем текущего пользователя

  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabCount = 3;
  user_service.UserProfile? _profile;
  Object? _profileLoadError;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowActionRunning = false;
  bool _isOpeningChat = false;
  final Set<int> _loadedTabs = {0};
  late final void Function(User?) _onSessionChanged;
  int? _postsListEpoch;
  int _postsRefreshGeneration = 0;
  bool _profileDataStarted = false;

  void _onTabIndexChanged() {
    if (_tabController.indexIsChanging) return;
    final idx = _tabController.index;
    if (_loadedTabs.add(idx) && mounted) {
      setState(() {});
    }
  }

  bool _isOwnProfileView({int? profileUserId}) {
    final me = AuthService.instance.currentUser?.id;
    if (me == null) return widget.userId == null;
    final target = widget.userId ?? profileUserId ?? me;
    return target == me;
  }

  bool _tabControllerReady = false;

  void _syncTabController({int? profileUserId}) {
    final count = _isOwnProfileView(profileUserId: profileUserId) ? 4 : 3;
    if (_tabControllerReady && _tabCount == count) return;

    final oldIndex = _tabControllerReady
        ? _tabController.index.clamp(0, count - 1)
        : 0;
    if (_tabControllerReady) {
      _tabController.removeListener(_onTabIndexChanged);
      _tabController.dispose();
    }
    _tabCount = count;
    _tabController = TabController(
      length: count,
      vsync: this,
      initialIndex: oldIndex,
    );
    _tabController.addListener(_onTabIndexChanged);
    _tabControllerReady = true;
    if (oldIndex >= count) {
      _loadedTabs
        ..clear()
        ..add(0);
    }
  }

  @override
  void initState() {
    super.initState();
    _postsListEpoch = AuthService.instance.currentUser?.id;
    _syncTabController();
    _onSessionChanged = (user) {
      if (widget.userId != null || !mounted) return;
      user_service.UserService.instance.profile.value = null;
      if (user == null) {
        setState(() {
          _loadedTabs
            ..clear()
            ..add(0);
          _tabController.index = 0;
          _postsListEpoch = null;
          _profile = null;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _loadedTabs
          ..clear()
          ..add(0);
        _tabController.index = 0;
        _postsListEpoch = user.id;
        _profile = _userProfileFromAuthUser(user);
      });
      _loadProfile();
    };
    AuthService.registerSessionListener(_onSessionChanged);
    final targetId = widget.userId ?? AuthService.instance.currentUser?.id;
    if (targetId != null) {
      final cached = ProfileCacheService.peek(targetId);
      if (cached != null) {
        _profile = cached;
        _isFollowing = cached.isFollowing ?? false;
        _isLoading = false;
      }
    }
    if (widget.userId == null) {
      final cached = AuthService.instance.currentUser;
      if (cached != null && _profile == null) {
        _profile = _userProfileFromAuthUser(cached);
        _isLoading = false;
      }
    }
    ShellTabVisibility.activeIndex.addListener(_onShellTabChanged);
    _maybeStartProfileLoading();
  }

  void _onShellTabChanged() {
    _maybeStartProfileLoading();
  }

  void _maybeStartProfileLoading() {
    if (widget.userId != null) {
      if (_profileDataStarted) return;
      _profileDataStarted = true;
      _loadProfile();
      return;
    }
    if (!ShellTabVisibility.profileActive) return;
    if (_profileDataStarted) return;
    _profileDataStarted = true;
    _loadProfile();
  }

  @override
  void dispose() {
    ShellTabVisibility.activeIndex.removeListener(_onShellTabChanged);
    AuthService.unregisterSessionListener(_onSessionChanged);
    if (_tabControllerReady) {
      _tabController.removeListener(_onTabIndexChanged);
      _tabController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_profile == null) {
      setState(() {
        _isLoading = true;
        _profileLoadError = null;
      });
    } else {
      setState(() => _profileLoadError = null);
    }

    try {
      if (widget.userId == null) {
        // Загружаем текущего пользователя (как в ProfileAuthScreen)
        var currentUser = AuthService.instance.currentUser;

        // Если пользователь не загружен, пытаемся загрузить из SharedPreferences
        if (currentUser == null) {
          try {
            final user = await AuthService.getCurrentUser();
            if (user != null) {
              AuthService.instance.setUserAfterAuth(user);
              currentUser = user;
            }
          } catch (e) {
            debugPrint('Ошибка при загрузке пользователя: $e');
          }
        }

        if (currentUser != null) {
          _profile = _userProfileFromAuthUser(currentUser);

          // Не блокируем экран: рендерим профиль сразу, API-обновление делаем фоном.
          if (mounted) {
            setState(() => _isLoading = false);
          }
          unawaited(_refreshOwnProfileFromApi());
          return;
        } else {
          _profile = null;
        }
      } else {
        // Загружаем профиль другого пользователя
        try {
          if (_profile == null) {
            final cached = ProfileCacheService.peek(widget.userId!) ??
                await ProfileCacheService.load(widget.userId!);
            if (cached != null && mounted) {
              setState(() {
                _profile = cached;
                _isFollowing = cached.isFollowing ?? false;
                _isLoading = false;
              });
            }
          }
          _profile = await user_service.UserService.getProfile(widget.userId!);
          _isFollowing = _profile?.isFollowing ?? false;
        } catch (e) {
          debugPrint(
              'Не удалось загрузить профиль пользователя ${widget.userId}: $e');
          _profile = null;
          _profileLoadError = e;
        }
      }
    } catch (e) {
      debugPrint('Ошибка при загрузке профиля: $e');
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null && widget.userId == null) {
        _profile = _userProfileFromAuthUser(currentUser);
      } else {
        _profile = null;
      }
    } finally {
      if (mounted) {
        _syncTabController(profileUserId: _profile?.user.id);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshOwnProfileFromApi() async {
    try {
      await user_service.UserService.instance.ensureProfileLoaded();
      final apiProfile = user_service.UserService.instance.profile.value;
      if (apiProfile != null && mounted) {
        setState(() {
          _profile = apiProfile;
        });
      }
    } catch (e) {
      debugPrint('Не удалось обновить профиль из API: $e');
    }
  }

  Widget _buildLazyTab(int index, Widget Function() builder) {
    if (!_loadedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    return builder();
  }

  Future<void> _openChat(User user) async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final conv = await ChatService.openDirectChat(user.id);
      if (!mounted) return;
      context.push(
        ChatThreadRoute.pathFor(conv),
        extra: conv,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось открыть чат'))),
      );
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_profile == null || widget.userId == null || _isFollowActionRunning) {
      return;
    }

    setState(() => _isFollowActionRunning = true);
    try {
      if (_isFollowing) {
        await user_service.UserService.unfollow(widget.userId!);
      } else {
        await user_service.UserService.follow(widget.userId!);
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = !_isFollowing;
        _profile = user_service.UserProfile(
          user: _profile!.user,
          stats: _profile!.stats,
          isFollowing: _isFollowing,
          isFollowedBy: _profile!.isFollowedBy,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFollowActionRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile == null) {
      final currentUser = AuthService.instance.currentUser;

      if (currentUser == null && widget.userId == null) {
        return const SizedBox.shrink();
      }
      if (widget.userId != null) {
        if (_profileLoadError != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Профиль')),
            body: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Не удалось загрузить профиль',
              subtitle: userVisibleError(
                _profileLoadError!,
                fallback: 'Проверьте сеть',
              ),
              action: FilledButton(
                onPressed: _loadProfile,
                child: const Text('Повторить'),
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Профиль')),
          body: const AppEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Пользователь не найден',
            subtitle: 'Возможно, профиль удалён или скрыт',
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _profile != null) return;
        final u = AuthService.instance.currentUser;
        if (u == null) return;
        setState(() {
          _profile = _userProfileFromAuthUser(u);
        });
      });
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = _profile!.user;
    final stats = _profile!.stats;
    final isOwnProfile = _isOwnProfileView(profileUserId: user.id);
    final tabs = <Tab>[
      const Tab(text: 'Общее'),
      const Tab(text: 'Рецепты'),
      const Tab(text: 'Рилсы'),
      if (isOwnProfile) const Tab(text: 'Сохранённые'),
    ];
    final tabViews = <Widget>[
      _buildLazyTab(0, _buildAllTab),
      _buildLazyTab(1, _buildRecipesTab),
      _buildLazyTab(2, _buildReelsTab),
      if (isOwnProfile) _buildLazyTab(3, _buildFavoritesTab),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnProfile ? 'Профиль' : user.name),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        actions: isOwnProfile
            ? [
                // Кнопка создать пост
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Создать пост или рилс',
                  onPressed: _openCreateContent,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Настройки приложения',
                  onPressed: () {
                    context.push(SettingsRoute.path);
                  },
                ),
              ]
            : null,
      ),
      body: AppGradientBackground(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _buildProfileHeader(user, stats, isOwnProfile),
              ),
            ];
          },
          body: Column(
            children: [
              longLabelTabBar(
                context: context,
                controller: _tabController,
                tabs: tabs,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: tabViews,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(
      User user, user_service.UserStats stats, bool isOwnProfile) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final avatarImage = resolvedAvatarImage(user.avatarUrl, decodeWidth: 200);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AppElevatedCard(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            AppAvatarRing(
              size: 96,
              child: ColoredBox(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                child: avatarImage == null
                    ? Center(
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      )
                    : Image(
                        image: avatarImage,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            if (user.username != null) ...[
              const SizedBox(height: 4),
              Text(
                '@${user.username}',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                user.bio!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.88),
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _ProfileStatsRow(
              postsCount: stats.postsCount,
              followersCount: stats.followersCount,
              followingCount: stats.followingCount,
              onFollowersTap: () => context.push(
                ProfileFollowersRoute.withUserId(_effectiveUserId),
              ),
              onFollowingTap: () => context.push(
                ProfileFollowingRoute.withUserId(_effectiveUserId),
              ),
            ),
            if (!isOwnProfile) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _isFollowActionRunning ? null : _toggleFollow,
                      child: Text(_isFollowing ? 'Отписаться' : 'Подписаться'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isOpeningChat ? null : () => _openChat(user),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Написать'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  int get _effectiveUserId => widget.userId ?? _profile!.user.id;

  Future<void> _openCreateContent() async {
    final published = await showCreateContentSheet(
      context,
      ref: ref,
      includeReel: true,
    );
    if (!mounted || !published) return;
    setState(() => _postsRefreshGeneration++);
    await _loadProfile();
  }

  Widget _postsList({required String? postType}) {
    return _PostsListWidget(
      key: ValueKey(
        'posts_${_effectiveUserId}_${postType ?? 'all'}_${_postsListEpoch}_$_postsRefreshGeneration',
      ),
      userId: _effectiveUserId,
      postType: postType,
    );
  }

  Widget _buildRecipesTab() {
    return _postsList(postType: 'recipe');
  }

  Widget _buildReelsTab() {
    return _postsList(postType: 'reel');
  }

  Widget _buildAllTab() {
    return _postsList(postType: null);
  }

  Widget _buildFavoritesTab() {
    final userId = widget.userId ?? _profile?.user.id;
    if (userId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // Показываем сохраненные посты (с подвкладками: Общее, Посты, Рилсы)
    return SavedPostsScreen(userId: userId, embedded: true);
  }
}

class _PostsListWidget extends StatefulWidget {
  final int userId;
  final String? postType;

  const _PostsListWidget({
    super.key,
    required this.userId,
    this.postType,
  });

  @override
  State<_PostsListWidget> createState() => _PostsListWidgetState();
}

class _PostsListWidgetState extends State<_PostsListWidget> {
  List<PostModel> _posts = [];
  Object? _loadError;
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cached = UserPostsCacheService.peek(
      widget.userId,
      postType: widget.postType,
    );
    if (cached != null && cached.isNotEmpty) {
      _posts = cached;
    }
    _loadPosts(refresh: true);
  }

  @override
  void didUpdateWidget(covariant _PostsListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.postType != widget.postType) {
      _posts = [];
      _offset = 0;
      _hasMore = true;
      _loadPosts(refresh: true);
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;
    final requestId = ++_loadGeneration;

    if (refresh) {
      final cached = UserPostsCacheService.peek(
        widget.userId,
        postType: widget.postType,
      );
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _posts = cached;
          _offset = cached.length;
          _hasMore = true;
          _isLoading = true;
          _loadError = null;
        });
      } else {
        setState(() {
          _isLoading = true;
          _posts = [];
          _offset = 0;
          _hasMore = true;
          _loadError = null;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final response = await UserPostsService.getUserPosts(
        userId: widget.userId,
        limit: 20,
        offset: refresh ? 0 : _offset,
        postType: widget.postType,
      );

      if (!mounted || requestId != _loadGeneration) return;
      final wallPosts = response.posts
          .where((post) => !PostPublisherDisplay.isChannel(post))
          .toList();
      setState(() {
        if (refresh) {
          _posts = wallPosts;
        } else {
          _posts.addAll(wallPosts);
        }
        _offset = _posts.length;
        _hasMore = _posts.length < response.total;
        _loadError = null;
      });
      if (refresh) {
        unawaited(
          UserPostsCacheService.save(
            widget.userId,
            postType: widget.postType,
            posts: wallPosts,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (refresh || _posts.isEmpty) {
            _loadError = e;
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
      return RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      if (_loadError != null) {
        return RefreshIndicator(
          onRefresh: () => _loadPosts(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.35,
                child: AppEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не удалось загрузить',
                  subtitle: userVisibleError(
                    _loadError!,
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
          padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
          children: const [
            SizedBox(height: 80),
            AppEmptyState(
              icon: Icons.post_add_outlined,
              title: 'Нет постов',
              subtitle: 'Здесь появятся публикации пользователя',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent * 0.8 &&
              !_isLoading &&
              _hasMore) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          primary: true,
          padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
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
              hideFeedHeader: true,
              onCommentTap: () =>
                  context.push(PostCommentsRoute.pathFor(post.id)),
              onPostDeleted: () {
                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                });
              },
              onAuthorTap: () => PostPublisherDisplay.open(context, post),
            );
          },
        ),
      ),
    );
  }
}

/// Ровная строка метрик профиля (равные колонки + разделители).
class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.postsCount,
    required this.followersCount,
    required this.followingCount,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  final int postsCount;
  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividerColor = scheme.outlineVariant.withValues(alpha: 0.45);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ProfileStatCell(
                value: '$postsCount',
                label: 'Посты',
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: dividerColor,
            ),
            Expanded(
              child: _ProfileStatCell(
                value: '$followersCount',
                label: 'Подписчики',
                onTap: onFollowersTap,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: dividerColor,
            ),
            Expanded(
              child: _ProfileStatCell(
                value: '$followingCount',
                label: 'Подписки',
                onTap: onFollowingTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatCell extends StatelessWidget {
  const _ProfileStatCell({
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.1,
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: content,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: content,
        ),
      ),
    );
  }
}
