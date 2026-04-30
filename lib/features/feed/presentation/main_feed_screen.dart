import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'subscriptions_feed_screen.dart';
import '../../community/presentation/reels_feed_screen.dart';
import 'new_feed_screen.dart';
import '../../../app/app_router.dart';
import '../../../services/notification_service.dart';

/// Главный экран ленты с табами: Подписки, Рекомендации, Рилсы
class MainFeedScreen extends ConsumerStatefulWidget {
  const MainFeedScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends ConsumerState<MainFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Начинаем с таба "Рекомендации" (индекс 1)
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    // Добавляем слушатель для загрузки данных при переключении вкладок
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // Вкладка полностью переключена, можно загружать данные
      // Это сработает и при первой загрузке, если вкладка уже активна
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HAN Eat'),
        bottom: TabBar(
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
            onPressed: () {
              context.push(SearchRoute.path);
            },
            tooltip: 'Поиск',
          ),
          // Кнопка уведомлений с badge
          Consumer(
            builder: (context, ref, child) {
              return FutureBuilder<int>(
                future: NotificationService.getUnreadCount(),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () {
                          context.push(NotificationsRoute.path);
                        },
                        tooltip: 'Уведомления',
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SubscriptionsFeedScreen(), // Подписки (слева)
          NewFeedScreen(hideScaffold: true), // Рекомендации (центр)
          ReelsFeedScreen(), // Рилсы (справа)
        ],
      ),
    );
  }
}

