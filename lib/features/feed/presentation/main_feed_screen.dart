import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../app/app_router.dart';
import '../../../app/web_app_path.dart';
import '../../../core/app/kitchen_removed_notice.dart';
import '../../../services/feed_ui_prefs.dart';
import '../../../models/post_types.dart';
import '../../reels/presentation/reels_feed_screen.dart';
import 'new_feed_screen.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/notification_bell_button.dart';
import '../../../widgets/telegram_ui.dart';
import '../application/feed_tab_layout.dart';
import 'feed_section_tabs.dart';
import '../../navigation/application/feed_scroll_chrome.dart';

/// Главный экран: одна лента (подписки) и рилсы.
class MainFeedScreen extends ConsumerStatefulWidget {
  const MainFeedScreen({super.key});

  @override
  ConsumerState<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends ConsumerState<MainFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _homeFeedType = 'all';
  FeedSortMode _homeSortMode = FeedSortMode.recent;
  bool _homeFollowingOnly = true;
  bool _reelsFollowingOnly = false;

  /// На web не грузим все табы сразу — только активный и уже открытые.
  final Set<int> _activatedTabs = kIsWeb ? {FeedTabLayout.home} : {0, 1};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: FeedTabLayout.count,
      vsync: this,
      initialIndex: FeedTabLayout.home,
    );
    _tabController.addListener(_onTabUi);
    feedScrollChromeActive.value = !FeedTabLayout.isReels(_tabController.index);
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
      FeedUiPrefs.loadHomeFollowingOnly(),
      FeedUiPrefs.loadReelsFollowingOnly(),
    ]);
    if (!mounted) return;
    var tab = results[0] as int;
    if (kIsWeb &&
        FeedShellLaunch.takeSkipReelsTab() &&
        FeedTabLayout.isReels(tab)) {
      tab = FeedTabLayout.home;
    }
    setState(() {
      _homeFeedType = results[1] as String;
      _homeSortMode = results[2] as FeedSortMode;
      _homeFollowingOnly = results[3] as bool;
      _reelsFollowingOnly = results[4] as bool;
    });
    if (tab != _tabController.index) {
      _tabController.index = tab;
      feedScrollChromeActive.value = !FeedTabLayout.isReels(tab);
      if (kIsWeb) _activatedTabs.add(tab);
    }
  }

  void _onTabUi() {
    if (_tabController.indexIsChanging) return;
    final isReels = FeedTabLayout.isReels(_tabController.index);
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
      child: SizedBox(
        height: kFeedChromeHeaderHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  const Spacer(),
                  NeoCircleAction(
                    tooltip: 'Моменты',
                    icon: Icons.auto_stories_outlined,
                    selected: false,
                    onPressed: () => context.push(StoriesRoute.path),
                  ),
                  const SizedBox(width: 6),
                  NeoCircleAction(
                    tooltip: 'Звёзды и кошелёк',
                    icon: Icons.stars_rounded,
                    selected: true,
                    onPressed: () => context.push(StarsWalletRoute.path),
                  ),
                  const SizedBox(width: 6),
                  const NotificationBellButton(),
                ],
              ),
            ),
            Expanded(
              child: FeedSectionTabs(
                controller: _tabController,
                homeFeedType: _homeFeedType,
                homeSortMode: _homeSortMode,
                homeFollowingOnly: _homeFollowingOnly,
                reelsFollowingOnly: _reelsFollowingOnly,
                onHomeFilterChanged: (value) {
                  setState(() => _homeFeedType = value);
                  unawaited(FeedUiPrefs.saveSubsFeedType(value));
                },
                onHomeSortChanged: (mode) {
                  setState(() => _homeSortMode = mode);
                  unawaited(FeedUiPrefs.saveSubsSortMode(mode));
                },
                onHomeFollowingChanged: (followingOnly) {
                  setState(() => _homeFollowingOnly = followingOnly);
                  unawaited(FeedUiPrefs.saveHomeFollowingOnly(followingOnly));
                },
                onReelsFilterChanged: (followingOnly) {
                  setState(() => _reelsFollowingOnly = followingOnly);
                  unawaited(
                      FeedUiPrefs.saveReelsFollowingOnly(followingOnly));
                },
              ),
            ),
          ],
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
                final isReels = FeedTabLayout.isReels(_tabController.index);
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
                  NewFeedScreen(
                    hideScaffold: true,
                    deferLoad: kIsWeb &&
                        !_activatedTabs.contains(FeedTabLayout.home),
                    externalFeedType: _homeFeedType,
                    externalSortMode: _homeSortMode,
                    externalFollowingOnly: _homeFollowingOnly,
                  ),
                  ReelsFeedScreen(
                    hideScaffold: true,
                    isTabVisible:
                        FeedTabLayout.isReels(_tabController.index),
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
