// Экран профиля пользователя
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

// Форма входа/регистрации
class _LoginForm extends StatefulWidget {
  final VoidCallback? onAuthSuccess;
  
  const _LoginForm({this.onAuthSuccess});
  
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance
          .signInWithEmail(_emailCtl.text.trim(), _passCtl.text.trim());
      if (mounted) {
        // Пользователь уже сохранен в _cachedUser через signInWithEmail
        // Но убедимся, что он также сохранен в SharedPreferences
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null) {
          print('✅ Пользователь в кэше после входа: ${currentUser.email}');
        } else {
          // Если не в кэше, пытаемся загрузить из SharedPreferences
          await Future.delayed(const Duration(milliseconds: 100));
          final user = await AuthService.getCurrentUser();
          if (user != null) {
            print('✅ Пользователь загружен из SharedPreferences после входа: ${user.email}');
            (AuthService.instance as dynamic)._cachedUser = user;
          } else {
            print('⚠️ Пользователь не найден ни в кэше, ни в SharedPreferences');
          }
        }
        // Вызываем callback для перезагрузки профиля
        widget.onAuthSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка входа: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _register() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance
          .createUserWithEmail(_emailCtl.text.trim(), _passCtl.text.trim());
      if (mounted) {
        // Пользователь уже сохранен в _cachedUser через createUserWithEmail
        // Но убедимся, что он также сохранен в SharedPreferences
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null) {
          print('✅ Пользователь в кэше после регистрации: ${currentUser.email}');
        } else {
          // Если не в кэше, пытаемся загрузить из SharedPreferences
          await Future.delayed(const Duration(milliseconds: 100));
          final user = await AuthService.getCurrentUser();
          if (user != null) {
            print('✅ Пользователь загружен из SharedPreferences после регистрации: ${user.email}');
            (AuthService.instance as dynamic)._cachedUser = user;
          } else {
            print('⚠️ Пользователь не найден ни в кэше, ни в SharedPreferences');
          }
        }
        // Вызываем callback для перезагрузки профиля
        widget.onAuthSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка регистрации: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _google() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) {
        // Обновляем кэш пользователя
        final user = await AuthService.getCurrentUser();
        if (user != null) {
          (AuthService.instance as dynamic)._cachedUser = user;
        }
        // Вызываем callback для перезагрузки профиля
        widget.onAuthSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка входа через Google: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Войдите в аккаунт',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _emailCtl,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passCtl,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          if (_loading)
            const CircularProgressIndicator()
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _signIn,
                child: const Text('Войти'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _register,
                child: const Text('Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Войти через Google'),
                onPressed: _google,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  final int? userId; // Если null, показываем текущего пользователя
  
  const ProfileScreen({Key? key, this.userId}) : super(key: key);
  
  static const routeName = '/profile';
  
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  user_service.UserProfile? _profile;
  bool _isLoading = true;
  bool _isFollowing = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProfile();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    
    try {
      if (widget.userId == null) {
        // Загружаем текущего пользователя (как в ProfileAuthScreen)
        var currentUser = AuthService.instance.currentUser;
        
        // Если пользователь не загружен, пытаемся загрузить из SharedPreferences
        if (currentUser == null) {
          print('⚠️ currentUser == null, пытаемся загрузить из SharedPreferences...');
          try {
            final user = await AuthService.getCurrentUser();
            if (user != null) {
              print('✅ Пользователь загружен из SharedPreferences: ${user.email}');
              // Обновляем кэш через приватное поле (временно)
              (AuthService.instance as dynamic)._cachedUser = user;
              currentUser = user;
            }
          } catch (e) {
            print('❌ Ошибка при загрузке пользователя: $e');
          }
        }
        
        print('🔍 Загрузка профиля: currentUser = ${currentUser?.id}, email = ${currentUser?.email}');
        
        if (currentUser != null) {
          // Сначала создаем профиль из данных пользователя (гарантированно)
          final authUser = currentUser;
          final userServiceUser = User(
            id: authUser.id,
            email: authUser.email,
            name: authUser.name,
            username: authUser.username,
            avatarUrl: authUser.avatarUrl,
            bio: authUser.bio,
            isPrivate: authUser.isPrivate,
            isAdmin: authUser.isAdmin,
            isModerator: authUser.isModerator,
            createdAt: authUser.createdAt,
          );
          _profile = user_service.UserProfile(
            user: userServiceUser,
            stats: user_service.UserStats(
              postsCount: 0,
              reelsCount: 0,
              savedCount: 0,
              followersCount: 0,
              followingCount: 0,
            ),
          );
          print('✅ Профиль создан из currentUser: ${_profile?.user.name}');
          
          // Затем пытаемся загрузить профиль из API (в фоне, не критично)
          try {
            await user_service.UserService.instance.ensureProfileLoaded();
            final apiProfile = user_service.UserService.instance.profile.value;
            if (apiProfile != null) {
              _profile = apiProfile;
              print('✅ Профиль обновлен из API');
            }
          } catch (e) {
            // Игнорируем ошибки загрузки из API - у нас уже есть профиль
            print('⚠️ Не удалось загрузить профиль из API: $e');
          }
        } else {
          // Пользователь не авторизован
          print('❌ currentUser == null');
          _profile = null;
        }
      } else {
        // Загружаем профиль другого пользователя
        try {
          _profile = await user_service.UserService.getProfile(widget.userId!);
          _isFollowing = _profile?.isFollowing ?? false;
        } catch (e) {
          print('⚠️ Не удалось загрузить профиль пользователя ${widget.userId}: $e');
          _profile = null;
        }
      }
    } catch (e) {
      print('⚠️ Ошибка при загрузке профиля: $e');
      // Если не удалось загрузить, создаем профиль из текущего пользователя
      final currentUser = AuthService.instance.currentUser;
      print('🔧 Catch блок: currentUser = ${currentUser?.id}, userId = ${widget.userId}');
      if (currentUser != null && widget.userId == null) {
        print('🔧 Создание профиля из currentUser в catch блоке');
        final authUser = currentUser;
        final userServiceUser = User(
          id: authUser.id,
          email: authUser.email,
          name: authUser.name,
          username: authUser.username,
          avatarUrl: authUser.avatarUrl,
          bio: authUser.bio,
          isPrivate: authUser.isPrivate,
          isAdmin: authUser.isAdmin,
          isModerator: authUser.isModerator,
          createdAt: authUser.createdAt,
        );
        _profile = user_service.UserProfile(
          user: userServiceUser,
          stats: user_service.UserStats(
            postsCount: 0,
            reelsCount: 0,
            savedCount: 0,
            followersCount: 0,
            followingCount: 0,
          ),
        );
        print('✅ Профиль создан в catch блоке: ${_profile?.user.name}');
      } else {
        print('❌ Не удалось создать профиль: currentUser = ${currentUser?.id}, userId = ${widget.userId}');
        _profile = null;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          isFollowing: !_isFollowing,
          isFollowedBy: _profile!.isFollowedBy,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
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
      // Проверяем, авторизован ли пользователь
      final currentUser = AuthService.instance.currentUser;
      print('🔍 ProfileScreen build: _profile == null, currentUser = ${currentUser?.id}');
      
      if (currentUser == null) {
        // Показываем форму входа/регистрации
        return Scaffold(
          appBar: AppBar(title: const Text('Профиль')),
          body: _LoginForm(
            onAuthSuccess: () {
              // После успешного входа/регистрации перезагружаем профиль
              _loadProfile();
            },
          ),
        );
      }
      // Пользователь авторизован, но профиль не загружен - создаем его прямо здесь
      print('⚠️ Профиль null в build, но currentUser существует. Создаем профиль...');
      final authUser = currentUser;
      final userServiceUser = User(
        id: authUser.id,
        email: authUser.email,
        name: authUser.name,
        username: authUser.username,
        avatarUrl: authUser.avatarUrl,
        bio: authUser.bio,
        isPrivate: authUser.isPrivate,
        isAdmin: authUser.isAdmin,
        isModerator: authUser.isModerator,
        createdAt: authUser.createdAt,
      );
      _profile = user_service.UserProfile(
        user: userServiceUser,
        stats: user_service.UserStats(
          postsCount: 0,
          reelsCount: 0,
          savedCount: 0,
          followersCount: 0,
          followingCount: 0,
        ),
      );
      print('✅ Профиль создан в build методе: ${_profile?.user.name}');
      // Обновляем состояние, чтобы перерисовать экран
      if (mounted) {
        setState(() {});
      }
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
                  tooltip: 'Создать пост',
                  onPressed: () {
                    context.push(CreatePostRoute.path);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Настройки профиля',
                  onPressed: () {
                    // Переход на экран редактирования профиля
                    context.pushNamed('profile_auth');
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
            TabBar(
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
                  _buildAllTab(),
                  _buildRecipesTab(),
                  _buildReelsTab(),
                  _buildFavoritesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProfileHeader(User user, user_service.UserStats stats, bool isOwnProfile) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Аватар (без кнопки смены - она в настройках)
          CircleAvatar(
            radius: 50,
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(
                    user.name[0].toUpperCase(),
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
  
  Widget _buildRecipesTab() {
    // Показываем только рецепты, которые выложил пользователь
    return _PostsListWidget(
      userId: widget.userId ?? _profile!.user.id,
      postType: 'recipe', // только рецепты
    );
  }
  
  Widget _buildReelsTab() {
    // Показываем только рилсы, которые выложил пользователь
    return _PostsListWidget(
      userId: widget.userId ?? _profile!.user.id,
      postType: 'reel', // Только короткие видео (рилсы)
    );
  }
  
  Widget _buildAllTab() {
    // Показываем все посты (и обычные, и рилсы, и рецепты)
    return _PostsListWidget(
      userId: widget.userId ?? _profile!.user.id,
      postType: null, // все посты
    );
  }
  
  Widget _buildFavoritesTab() {
    final userId = widget.userId ?? _profile?.user.id;
    if (userId == null) {
      return const Center(child: Text('Войдите, чтобы видеть избранное'));
    }
    // Показываем сохраненные посты (с подвкладками: Общее, Посты, Рилсы)
    return SavedPostsScreen(userId: userId);
  }
}

class _PostsListWidget extends StatefulWidget {
  final int userId;
  final String? postType;
  
  const _PostsListWidget({
    required this.userId,
    this.postType,
  });
  
  @override
  State<_PostsListWidget> createState() => _PostsListWidgetState();
}

class _PostsListWidgetState extends State<_PostsListWidget> {
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.post_add, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет постов',
              style: TextStyle(color: Colors.grey[600]),
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

