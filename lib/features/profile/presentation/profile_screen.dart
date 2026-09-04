// Экран профиля пользователя
import 'dart:async';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:han_eat/services/auth_service.dart';
import 'package:han_eat/services/user_service.dart' as user_service;
import 'package:han_eat/services/user_posts_service.dart';
import 'package:han_eat/services/profile_cache_service.dart';
import 'package:han_eat/services/user_posts_cache_service.dart';
import 'package:han_eat/services/paid_features_service.dart';
import 'package:han_eat/models/post_model.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../saved/presentation/saved_posts_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/core/theme/app_tokens.dart';
import '../../chat/application/chat_open_direct.dart';
import '../../../models/chat_models.dart';
import 'package:han_eat/widgets/app_avatar.dart';
import 'package:han_eat/widgets/stars_pay_helper.dart';
import 'package:uuid/uuid.dart';
import '../../navigation/application/shell_tab_visibility.dart';
import 'package:han_eat/core/layout/floating_bottom_padding.dart';
import 'package:han_eat/widgets/app_empty_state.dart';
import 'package:han_eat/widgets/app_gradient_background.dart';
import 'package:han_eat/widgets/telegram_ui.dart';
import '../../content/create_content_actions.dart';
import '../../chat/presentation/widgets/star_gift_picker_sheet.dart';
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
  bool _isSendingGift = false;
  bool _isSendingTip = false;
  final Set<int> _loadedTabs = {0};
  late final void Function(User?) _onSessionChanged;
  int? _postsListEpoch;
  int _postsRefreshGeneration = 0;
  bool _profileDataStarted = false;
  List<UserStarGift> _profileGifts = const [];

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
    final count = 2 + (_isOwnProfileView(profileUserId: profileUserId) ? 1 : 0);
    if (_tabControllerReady && _tabCount == count) return;

    final oldIndex =
        _tabControllerReady ? _tabController.index.clamp(0, count - 1) : 0;
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
        unawaited(_loadProfileGifts());
      }
    }
  }

  Future<void> _loadProfileGifts() async {
    final userId = widget.userId ?? _profile?.user.id;
    if (userId == null) return;
    try {
      final gifts = await PaidFeaturesService.listUserGifts(userId);
      if (!mounted) return;
      setState(() => _profileGifts = gifts);
    } catch (_) {
      // Gifts are optional chrome — keep profile usable offline/errors.
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
        unawaited(_loadProfileGifts());
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

  ChatUserBrief _briefFor(User user) => ChatUserBrief(
        id: user.id,
        name: user.name,
        username: user.username,
        avatarUrl: user.avatarUrl,
      );

  Future<void> _openChat(User user) async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final conv = await ChatOpenDirect.openNow(user.id, peer: _briefFor(user));
      if (!mounted) return;
      context.push(
        ChatThreadRoute.pathFor(conv),
        extra: conv,
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallback: 'Не удалось открыть чат',
        onRetry: () => unawaited(_openChat(user)),
      );
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _sendGiftFromProfile(User user) async {
    if (_isSendingGift) return;
    final draft = await showStarGiftSendFlow(context);
    if (draft == null || !mounted) return;
    setState(() => _isSendingGift = true);
    try {
      final conv = await ChatOpenDirect.openNow(user.id, peer: _briefFor(user));
      if (!mounted) return;
      final idem =
          'flutter:profile-gift:${user.id}:${draft.gift.id}:${const Uuid().v4()}';
      final real = conv.id > 0 ? conv : await ChatOpenDirect.resolve(user.id);
      await PaidFeaturesService.sendGift(
        giftId: draft.gift.id,
        conversationId: real.id,
        message: draft.message,
        hideName: draft.hideName,
        idempotencyKey: idem,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.hideName
                ? 'Подарок ${draft.gift.emoji} отправлен анонимно'
                : 'Подарок ${draft.gift.emoji} отправлен',
          ),
        ),
      );
      context.push(ChatThreadRoute.pathFor(real), extra: real);
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(
        context,
        e,
        onRetry: () => unawaited(_sendGiftFromProfile(user)),
      );
    } finally {
      if (mounted) setState(() => _isSendingGift = false);
    }
  }

  Future<void> _sendStarsFromProfile(User user) async {
    if (_isSendingTip) return;
    final draft = await pickStarsTipDraft(
      context,
      title: 'Отправить звёзды ${user.name}',
      subtitle: 'Звёзды появятся сообщением в личке, как в Telegram.',
    );
    if (draft == null || !mounted) return;
    setState(() => _isSendingTip = true);
    try {
      final result = await PaidFeaturesService.donate(
        recipientId: user.id,
        amountStars: draft.amount,
        message: draft.message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Отправлено ${draft.amount} ★. Баланс: ${result.balance}',
          ),
        ),
      );
      if (result.conversationId != null) {
        final conv = await ChatOpenDirect.openNow(user.id, peer: _briefFor(user));
        if (!mounted) return;
        context.push(ChatThreadRoute.pathFor(conv), extra: conv);
      }
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(
        context,
        e,
        onRetry: () => unawaited(_sendStarsFromProfile(user)),
      );
    } finally {
      if (mounted) setState(() => _isSendingTip = false);
    }
  }

  Future<void> _buyProfileGift(UserStarGift gift) async {
    final price = gift.listedStars ?? 0;
    if (price <= 0) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить ${gift.title}',
      body: gift.serialLabel.isNotEmpty
          ? '${gift.emoji} ${gift.serialLabel}'
          : gift.emoji,
      amountStars: price,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    try {
      await PaidFeaturesService.buyListedGift(gift.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${gift.emoji} ${gift.title} теперь ваш')),
      );
      unawaited(_loadProfileGifts());
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(
        context,
        e,
        onRetry: () => unawaited(_buyProfileGift(gift)),
      );
    }
  }

  Future<void> _showProfileGiftDetails(UserStarGift gift) async {
    final scheme = Theme.of(context).colorScheme;
    final sender = gift.senderLabel;
    final me = AuthService.instance.currentUser?.id;
    final canBuy = gift.isListed && me != null && me != gift.ownerId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(gift.emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                  gift.title,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (gift.serialLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    gift.serialLabel,
                    style: TextStyle(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${gift.stars} ★',
                  style: TextStyle(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                if (sender.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'От $sender',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (gift.note != null && gift.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    gift.note!.trim(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (gift.isListed) ...[
                  const SizedBox(height: 12),
                  Text(
                    'В продаже · ${gift.listedStars} ★',
                    style: TextStyle(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (canBuy) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_buyProfileGift(gift));
                      },
                      child: Text('Купить · ${gift.listedStars} ★'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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
        showErrorSnackBar(
          context,
          e,
          onRetry: () => unawaited(_toggleFollow()),
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
          body: AppEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Пользователь не найден',
            subtitle: 'Возможно, профиль удалён или скрыт',
            action: FilledButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(FeedRoute.path);
                }
              },
              child: const Text('Назад'),
            ),
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
      const Tab(text: 'Рилсы'),
      if (isOwnProfile) const Tab(text: 'Сохранённые'),
    ];
    final tabViews = <Widget>[
      _buildLazyTab(0, _buildAllTab),
      _buildLazyTab(1, _buildReelsTab),
      if (isOwnProfile) _buildLazyTab(2, _buildFavoritesTab),
    ];

    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(user.name),
        actions: isOwnProfile
            ? [
                NeoCircleAction(
                  icon: Icons.add,
                  tooltip: 'Создать пост или рилс',
                  onPressed: _openCreateContent,
                ),
                const SizedBox(width: 4),
                NeoCircleAction(
                  icon: Icons.edit_outlined,
                  tooltip: 'Редактировать профиль',
                  onPressed: () => context.push(ProfileAuthRoute.path),
                ),
                const SizedBox(width: 4),
                NeoCircleAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Настройки приложения',
                  onPressed: () {
                    context.push(SettingsRoute.path);
                  },
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: _buildProfileHeader(user, stats, isOwnProfile),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedProfileTabsDelegate(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NeoUnderlineTabs(
                    controller: _tabController,
                    tabs: tabs,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: tabViews,
        ),
      ),
    ),
    );
  }

  Widget _buildProfileHeader(
      User user, user_service.UserStats stats, bool isOwnProfile) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return NeoGlassCard(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      padding: EdgeInsets.zero,
      radius: 28,
      gradient: RadialGradient(
        center: const Alignment(0, -0.72),
        radius: 0.92,
        colors: [
          scheme.primary.withValues(alpha: 0.34),
          scheme.primary.withValues(alpha: 0.10),
          scheme.surfaceContainer.withValues(alpha: 0.78),
        ],
        stops: const [0, 0.42, 1],
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: user.profileDecoration
                        ? [
                            const Color(0xFFFFD54F),
                            scheme.primary,
                            scheme.tertiary,
                          ]
                        : [
                            scheme.primary.withValues(alpha: 0.88),
                            scheme.tertiary.withValues(alpha: 0.58),
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.32),
                      blurRadius: 34,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerLowest,
                  ),
                  child: AppUserAvatar(
                    imageUrl: user.avatarUrl,
                    displayName: user.name,
                    radius: 50,
                    fontSize: 38,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Builder(
                builder: (context) {
                  UserStarGift? worn;
                  for (final g in _profileGifts) {
                    if (g.isWorn) {
                      worn = g;
                      break;
                    }
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                      if (user.premiumBadge) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Подписка HanWe',
                          child: InkWell(
                            onTap: isOwnProfile
                                ? () => context.push(FlexSubscriptionRoute.path)
                                : null,
                            customBorder: const CircleBorder(),
                            child: Icon(
                              Icons.verified_rounded,
                              color: scheme.primary,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                      if (worn != null) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: worn.serialLabel.isNotEmpty
                              ? '${worn.title} ${worn.serialLabel}'
                              : worn.title,
                          child: Text(
                            worn.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (user.username != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    '@${user.username}',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  user.bio!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              if (_profileGifts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: isOwnProfile
                            ? () => context.push(StarGiftsInventoryRoute.path)
                            : () => context.push(
                                  StarGiftsMarketplaceRoute.path,
                                ),
                        borderRadius: BorderRadius.circular(8),
                        child: Text(
                          isOwnProfile ? 'Подарки' : 'Подарки профиля',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final g in _profileGifts.take(12))
                            Tooltip(
                              message: () {
                                final base = g.serialLabel.isNotEmpty
                                    ? '${g.title} ${g.serialLabel} · ${g.stars} ★'
                                    : '${g.title} · ${g.stars} ★';
                                final sender = g.senderLabel;
                                return sender.isEmpty
                                    ? base
                                    : '$base · от $sender';
                              }(),
                              child: InkWell(
                                onTap: () => unawaited(
                                  _showProfileGiftDetails(g),
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      g.emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    if (g.isListed)
                                      Text(
                                        '${g.listedStars} ★',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: scheme.secondary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    else if (g.serial != null)
                                      Text(
                                        '#${g.serial}',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (_profileGifts.length > 12)
                            Text(
                              '+${_profileGifts.length - 12}',
                              style: textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _ProfileStatsRow(
                postsCount: stats.postsCount,
                followersCount: stats.followersCount,
                followingCount: stats.followingCount,
                onPostsTap: () {
                  if (_tabControllerReady) {
                    _tabController.animateTo(0);
                  }
                },
                onFollowersTap: () => context.push(
                  ProfileFollowersRoute.withUserId(_effectiveUserId),
                ),
                onFollowingTap: () => context.push(
                  ProfileFollowingRoute.withUserId(_effectiveUserId),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!isOwnProfile) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _isFollowActionRunning ? null : _toggleFollow,
                        child:
                            Text(_isFollowing ? 'Отписаться' : 'Подписаться'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _isOpeningChat ? null : () => _openChat(user),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Написать'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSendingGift
                            ? null
                            : () => unawaited(_sendGiftFromProfile(user)),
                        icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                        label: const Text('Подарок'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSendingTip
                            ? null
                            : () => unawaited(_sendStarsFromProfile(user)),
                        icon: const Icon(Icons.star_rounded, size: 18),
                        label: const Text('Звёзды'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
      onCreate: _isOwnProfileView(profileUserId: _effectiveUserId)
          ? () => unawaited(_openCreateContent())
          : null,
    );
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
  final VoidCallback? onCreate;

  const _PostsListWidget({
    super.key,
    required this.userId,
    this.postType,
    this.onCreate,
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

  List<PostModel> _visibleProfilePosts(List<PostModel> posts) {
    // Legacy recipe posts are normal profile posts in HanWe.
    return posts.where((post) => !PostPublisherDisplay.isChannel(post)).toList();
  }

  @override
  void initState() {
    super.initState();
    final cached = UserPostsCacheService.peek(
      widget.userId,
      postType: widget.postType,
    );
    if (cached != null && cached.isNotEmpty) {
      _posts = _visibleProfilePosts(cached);
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
        final visibleCached = _visibleProfilePosts(cached);
        setState(() {
          _posts = visibleCached;
          _offset = visibleCached.length;
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
      final rawCount = response.posts.length;
      final wallPosts = _visibleProfilePosts(response.posts);
      setState(() {
        if (refresh) {
          _posts = wallPosts;
        } else {
          _posts.addAll(wallPosts);
        }
        _offset = refresh ? rawCount : _offset + rawCount;
        _hasMore = _offset < response.total;
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
      final isReel = widget.postType == 'reel';
      final canCreate = widget.onCreate != null;
      return RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
          children: [
            const SizedBox(height: 80),
            AppEmptyState(
              icon: isReel
                  ? Icons.video_library_outlined
                  : Icons.post_add_outlined,
              title: isReel ? 'Нет рилсов' : 'Нет постов',
              subtitle: canCreate
                  ? (isReel
                      ? 'Снимите первый рилс'
                      : 'Опубликуйте первый пост')
                  : 'Здесь появятся публикации пользователя',
              action: canCreate
                  ? FilledButton.icon(
                      onPressed: widget.onCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(isReel ? 'Снять рилс' : 'Создать пост'),
                    )
                  : null,
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
    this.onPostsTap,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  final int postsCount;
  final int followersCount;
  final int followingCount;
  final VoidCallback? onPostsTap;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividerColor = scheme.outlineVariant.withValues(alpha: 0.45);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
          width: 0.7,
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
                onTap: onPostsTap,
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

class _PinnedProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  _PinnedProfileTabsDelegate({
    required this.child,
    required this.height,
  });

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: overlapsContent
          ? scheme.surface.withValues(alpha: 0.94)
          : Colors.transparent,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedProfileTabsDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
