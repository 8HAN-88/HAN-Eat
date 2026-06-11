import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subscriptions_feed_screen.dart';
import '../../reels/presentation/reels_feed_screen.dart';
import 'new_feed_screen.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/notification_bell_button.dart';
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
  bool _reelsFollowingOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(_onTabUi);
    feedScrollChromeActive.value = _tabController.index != 2;
  }

  void _onTabUi() {
    if (_tabController.indexIsChanging) return;
    final isReels = _tabController.index == 2;
    feedScrollChromeActive.value = !isReels;
    if (isReels) resetFeedScrollChrome();
    if (mounted) setState(() {});
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
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kFeedChromeHeaderHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FeedSectionTabs(
                  controller: _tabController,
                  subsFeedType: _subsFeedType,
                  recFeedType: _recFeedType,
                  reelsFollowingOnly: _reelsFollowingOnly,
                  onSubsFilterChanged: (value) {
                    setState(() => _subsFeedType = value);
                  },
                  onRecFilterChanged: (value) {
                    setState(() => _recFeedType = value);
                  },
                  onReelsFilterChanged: (followingOnly) {
                    setState(() => _reelsFollowingOnly = followingOnly);
                  },
                ),
              ),
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
                    externalFeedType: _subsFeedType,
                  ),
                  NewFeedScreen(
                    hideScaffold: true,
                    externalFeedType: _recFeedType,
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
                color: scheme.surface.withValues(alpha: 0.97),
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
