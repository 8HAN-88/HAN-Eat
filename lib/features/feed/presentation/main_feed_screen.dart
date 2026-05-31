import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'subscriptions_feed_screen.dart';
import '../../reels/presentation/reels_feed_screen.dart';
import 'new_feed_screen.dart';
import '../../../app/app_router.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/notification_bell_button.dart';
import '../../../core/layout/long_label_tab_bar.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../content/create_content_actions.dart';

/// Главный экран ленты с табами: Подписки, Рекомендации, Рилсы
class MainFeedScreen extends ConsumerStatefulWidget {
  const MainFeedScreen({super.key});

  @override
  ConsumerState<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends ConsumerState<MainFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Тип ленты для таба «Рекомендации» ([NewFeedScreen] с [externalFeedType]).
  String _recFeedType = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(_onTabUi);
  }

  void _onTabUi() {
    if (_tabController.indexIsChanging) return;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabUi);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        bottom: longLabelTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Подписки'),
            Tab(text: 'Рекомендации'),
            Tab(text: 'Рилсы'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(SearchRoute.path),
            tooltip: 'Поиск',
          ),
          if (_tabController.index == 1)
            PopupMenuButton<String>(
              tooltip: 'Фильтр ленты',
              onSelected: (value) {
                setState(() => _recFeedType = value);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'all',
                  child: Text(
                    'Все',
                    style: TextStyle(
                      fontWeight:
                          _recFeedType == 'all' ? FontWeight.bold : null,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'photos',
                  child: Text(
                    'Фото',
                    style: TextStyle(
                      fontWeight:
                          _recFeedType == 'photos' ? FontWeight.bold : null,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'recipes',
                  child: Text(
                    'Рецепты',
                    style: TextStyle(
                      fontWeight:
                          _recFeedType == 'recipes' ? FontWeight.bold : null,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'reels',
                  child: Text(
                    'Рилсы',
                    style: TextStyle(
                      fontWeight:
                          _recFeedType == 'reels' ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.filter_list),
              ),
            ),
          const NotificationBellButton(),
        ],
      ),
      body: AppGradientBackground(
        child: TabBarView(
          controller: _tabController,
          children: [
            const SubscriptionsFeedScreen(),
            NewFeedScreen(
              hideScaffold: true,
              externalFeedType: _recFeedType,
            ),
            ReelsFeedScreen(
              hideScaffold: true,
              onCreateReel: () => openCreateReel(context, ref: ref),
            ),
          ],
        ),
      ),
      floatingActionButton: floatingActionButtonClearOfBottomNav(
        context,
        child: FloatingActionButton.extended(
          onPressed: () async {
            if (_tabController.index == 2) {
              await openCreateReel(context, ref: ref);
            } else {
              await showCreateContentSheet(context, ref: ref);
            }
          },
          icon: Icon(
            _tabController.index == 2 ? Icons.videocam_outlined : Icons.add,
          ),
          label: Text(_tabController.index == 2 ? 'Создать рилс' : 'Создать'),
        ),
      ),
    );
  }
}
