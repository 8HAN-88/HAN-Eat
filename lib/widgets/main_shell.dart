import 'package:flutter/material.dart';
import '../features/feed/presentation/main_feed_screen.dart';
import '../features/community/presentation/community_screen.dart';
import '../features/community/presentation/community_upload_screen.dart';
import '../features/favorites/favorites_page.dart';
import '../features/shopping/shopping_page.dart';

/// Устаревшая нижняя навигация (4 таба). Используйте [RootShell] + GoRouter.
@Deprecated('Use RootShell via GoRouter (Feed / Channels / Menu / Profile)')
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  int _index = 0;

  final List<Widget> _pages = const [
    MainFeedScreen(),
    CommunityScreen(),
    FavoritesPage(),
    ShoppingPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Внутренние вкладки уже с собственным AppBar — иначе двойная шапка.
      appBar: null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_index],
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
      ),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              heroTag: 'main_shell_upload',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CommunityUploadScreen(),
                ),
              ),
              child: const Icon(Icons.cloud_upload),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Главная'),
          BottomNavigationBarItem(
              icon: Icon(Icons.group_outlined), label: 'Сообщество'),
          BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border), label: 'Избранное'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined), label: 'Покупки'),
        ],
      ),
    );
  }
}
