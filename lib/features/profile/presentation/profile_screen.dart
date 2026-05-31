// Экран профиля пользователя
import 'dart:async';
import '../../../utils/api_error_parser.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/user_service.dart' as user_service;
import '../../../../services/user_posts_service.dart';
import '../../../../models/post_model.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../saved/presentation/saved_posts_screen.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/app_router.dart';
import '../../../../core/layout/long_label_tab_bar.dart';
import '../../../../widgets/app_empty_state.dart';
import '../../content/create_content_actions.dart';

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
  user_service.UserProfile? _profile;
  Object? _profileLoadError;
  bool _isLoading = true;
  bool _isFollowing = false;
  final Set<int> _loadedTabs = {0};
  late final void Function(User?) _onSessionChanged;
  int? _postsListEpoch;
  int _postsRefreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _postsListEpoch = AuthService.instance.currentUser?.id;
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final idx = _tabController.index;
      if (_loadedTabs.add(idx) && mounted) {
        setState(() {});
      }
    });
    _onSessionChanged = (user) {
      if (widget.userId != null || !mounted) return;
      user_service.UserService.instance.profile.value = null;
      setState(() {
        _loadedTabs
          ..clear()
          ..add(0);
        _tabController.index = 0;
        _postsListEpoch = user?.id;
        _profile = user != null ? _userProfileFromAuthUser(user) : null;
      });
      _loadProfile();
    };
    AuthService.registerSessionListener(_onSessionChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    AuthService.unregisterSessionListener(_onSessionChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _profileLoadError = null;
    });

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

  Future<void> _toggleFollow() async {
    if (_profile == null || widget.userId == null) return;

    try {
      if (_isFollowing) {
        await user_service.UserService.unfollow(widget.userId!);
      } else {
        await user_service.UserService.follow(widget.userId!);
      }
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(LoginRoute.path);
        });
        return Scaffold(
          appBar: AppBar(title: const Text('Профиль')),
          body: const Center(child: CircularProgressIndicator()),
        );
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
    final isOwnProfile = widget.userId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.name),
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
      body: NestedScrollView(
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
              controller: _tabController,
              tabs: const [
                Tab(text: 'Общее'),
                Tab(text: 'Рецепты'),
                Tab(text: 'Рилсы'),
                Tab(text: 'Избранное'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLazyTab(0, _buildAllTab),
                  _buildLazyTab(1, _buildRecipesTab),
                  _buildLazyTab(2, _buildReelsTab),
                  _buildLazyTab(3, _buildFavoritesTab),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(
      User user, user_service.UserStats stats, bool isOwnProfile) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Аватар (без кнопки смены - она в настройках)
          CircleAvatar(
            radius: 50,
            backgroundImage:
                user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
            child: user.avatarUrl == null
                ? Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 40),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          // Имя и username
          Text(
            user.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (user.username != null) ...[
            const SizedBox(height: 4),
            Text(
              '@${user.username}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              user.bio!,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          // Статистика
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(label: 'Посты', value: '${stats.postsCount}'),
              _StatItem(label: 'Подписчики', value: '${stats.followersCount}'),
              _StatItem(label: 'Подписки', value: '${stats.followingCount}'),
            ],
          ),
          const SizedBox(height: 16),
          // Кнопки действий
          if (!isOwnProfile)
            FilledButton(
              onPressed: _toggleFollow,
              child: Text(_isFollowing ? 'Отписаться' : 'Подписаться'),
            ),
        ],
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
      return AppEmptyState(
        icon: Icons.bookmark_border,
        title: 'Войдите в аккаунт',
        subtitle: 'Сохранённые посты доступны после входа',
        action: FilledButton(
          onPressed: () => context.push(LoginRoute.path),
          child: const Text('Войти'),
        ),
      );
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

  @override
  void initState() {
    super.initState();
    _loadPosts();
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

    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMore = true;
        _loadError = null;
      }
    });

    try {
      final response = await UserPostsService.getUserPosts(
        userId: widget.userId,
        limit: 20,
        offset: refresh ? 0 : _offset,
        postType: widget.postType,
      );

      setState(() {
        if (refresh) {
          _posts = response.posts;
        } else {
          _posts.addAll(response.posts);
        }
        _offset = _posts.length;
        _hasMore = _posts.length < response.total;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (refresh) {
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
              onAuthorTap: () {
                context.push(ProfileRoute.withUserId(post.userId));
              },
            );
          },
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
