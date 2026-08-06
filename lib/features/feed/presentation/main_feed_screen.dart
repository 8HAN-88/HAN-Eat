import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../app/app_router.dart';
import '../../../core/app/kitchen_removed_notice.dart';
import '../../../services/feed_ui_prefs.dart';
import '../../../models/post_types.dart';
import 'subscriptions_feed_screen.dart';
import '../../reels/presentation/reels_feed_screen.dart';
import 'new_feed_screen.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/notification_bell_button.dart';
import '../../../widgets/telegram_ui.dart';
import 'feed_section_tabs.dart';
import '../../navigation/application/feed_scroll_chrome.dart';

/// Главный экран ленты с табами: Подписки, Рекомендации, Рилсы
class MainFeedScreen extends ConsumerStatefulWidget {
  const MainFeedScreen({super.key});

  @override
  ConsumerState<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends ConsumerState<MainFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _subsFeedType = 'all';
  String _recFeedType = 'all';
  FeedSortMode _subsSortMode = FeedSortMode.recent;
  FeedSortMode _recSortMode = FeedSortMode.personalized;
  bool _reelsFollowingOnly = false;

  /// На web не грузим все табы сразу — только активный и уже открытые.
  final Set<int> _activatedTabs = kIsWeb ? {1} : {0, 1, 2};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(_onTabUi);
    feedScrollChromeActive.value = _tabController.index != 2;
    unawaited(_restoreUiPrefs());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !KitchenRemovedNotice.take()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Этот раздел удалён. HanWe — мессенджер: чаты, лента и каналы.'),
        ),
      );
    });
  }

  Future<void> _restoreUiPrefs() async {
    final results = await Future.wait([
      FeedUiPrefs.loadTabIndex(),
      FeedUiPrefs.loadSubsFeedType(),
      FeedUiPrefs.loadSubsSortMode(),
      FeedUiPrefs.loadRecFeedType(),
      FeedUiPrefs.loadRecSortMode(),
      FeedUiPrefs.loadReelsFollowingOnly(),
    ]);
    if (!mounted) return;
    final tab = results[0] as int;
    setState(() {
      _subsFeedType = results[1] as String;
      _subsSortMode = results[2] as FeedSortMode;
      _recFeedType = results[3] as String;
      _recSortMode = results[4] as FeedSortMode;
      _reelsFollowingOnly = results[5] as bool;
    });
    if (tab != _tabController.index) {
      _tabController.index = tab;
      feedScrollChromeActive.value = tab != 2;
      if (kIsWeb) _activatedTabs.add(tab);
    }
  }

  void _onTabUi() {
    if (_tabController.indexIsChanging) return;
    final isReels = _tabController.index == 2;
    feedScrollChromeActive.value = !isReels;
    if (isReels) resetFeedScrollChrome();
    unawaited(FeedUiPrefs.saveTabIndex(_tabController.index));
    if (kIsWeb) {
      final added = _activatedTabs.add(_tabController.index);
      if (added && mounted) setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabUi);
    _tabController.dispose();
    resetFeedScrollChrome();
    feedScrollChromeActive.value = true;
    super.dispose();
  }

  Widget _buildFeedChromeHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: SizedBox(
          height: kFeedChromeHeaderHeight - 16,
          child: Row(
            children: [
              Expanded(
                child: FeedSectionTabs(
                  controller: _tabController,
                  subsFeedType: _subsFeedType,
                  subsSortMode: _subsSortMode,
                  recFeedType: _recFeedType,
                  recSortMode: _recSortMode,
                  reelsFollowingOnly: _reelsFollowingOnly,
                  onSubsFilterChanged: (value) {
                    setState(() => _subsFeedType = value);
                    unawaited(FeedUiPrefs.saveSubsFeedType(value));
                  },
                  onSubsSortChanged: (mode) {
                    setState(() => _subsSortMode = mode);
                    unawaited(FeedUiPrefs.saveSubsSortMode(mode));
                  },
                  onRecFilterChanged: (value) {
                    setState(() => _recFeedType = value);
                    unawaited(FeedUiPrefs.saveRecFeedType(value));
                  },
                  onRecSortChanged: (mode) {
                    setState(() => _recSortMode = mode);
                    unawaited(FeedUiPrefs.saveRecSortMode(mode));
                  },
                  onReelsFilterChanged: (followingOnly) {
                    setState(() => _reelsFollowingOnly = followingOnly);
                    unawaited(
                        FeedUiPrefs.saveReelsFollowingOnly(followingOnly));
                  },
                ),
              ),
              const SizedBox(width: 10),
              NeoCircleAction(
                tooltip: 'Моменты',
                icon: Icons.auto_stories_outlined,
                selected: false,
                onPressed: () => context.push(StoriesRoute.path),
              ),
              const SizedBox(width: 8),
              NeoCircleAction(
                tooltip: 'Звёзды и кошелёк',
                icon: Icons.stars_rounded,
                selected: true,
                onPressed: () => context.push(StarsWalletRoute.path),
              ),
              const SizedBox(width: 8),
              const NotificationBellButton(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppGradientBackground(
            child: ValueListenableBuilder<bool>(
              valueListenable: feedScrollChromeHidden,
              builder: (context, hidden, child) {
                final isReels = _tabController.index == 2;
                final topInset = isReels
                    ? 0.0
                    : (hidden ? 0.0 : feedChromeTopInset(context));
                return AnimatedPadding(
                  duration: kFeedScrollChromeDuration,
                  curve: kFeedScrollChromeCurve,
                  padding: EdgeInsets.only(top: topInset),
                  child: child,
                );
              },
              child: TabBarView(
                controller: _tabController,
                children: [
                  SubscriptionsFeedScreen(
                    deferLoad: kIsWeb && !_activatedTabs.contains(0),
                    externalFeedType: _subsFeedType,
                    externalSortMode: _subsSortMode,
                  ),
                  NewFeedScreen(
                    hideScaffold: true,
                    deferLoad: kIsWeb && !_activatedTabs.contains(1),
                    externalFeedType: _recFeedType,
                    externalSortMode: _recSortMode,
                  ),
                  ReelsFeedScreen(
                    hideScaffold: true,
                    isTabVisible: _tabController.index == 2,
                    externalFollowingOnly: _reelsFollowingOnly,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: feedScrollChromeHidden,
              builder: (context, hidden, child) {
                return IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedSlide(
                    duration: kFeedScrollChromeDuration,
                    curve: kFeedScrollChromeCurve,
                    offset: hidden ? const Offset(0, -1) : Offset.zero,
                    child: child!,
                  ),
                );
              },
              child: Material(
                color: scheme.surfaceContainerLowest.withValues(alpha: 0.96),
                elevation: 0,
                shadowColor: Colors.transparent,
                child: _buildFeedChromeHeader(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
