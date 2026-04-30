import 'package:flutter/material.dart';
import '../features/feed/home_page.dart';
import '../features/community/community_page.dart';
import '../features/favorites/favorites_page.dart';
import '../features/shopping/shopping_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({Key? key}) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  int _index = 0;
  static const _titles = ['Home', 'Community', 'Favorites', 'Shopping'];

  final List<Widget> _pages = const [
    HomePage(),
    CommunityPage(),
    FavoritesPage(),
    ShoppingPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: true,
        elevation: 2,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_index],
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
      ),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              heroTag: 'main_shell_upload',
              onPressed: () => Navigator.pushNamed(context,
                  '/community'), // Community page already supports upload FAB; here navigate for full screen
              child: const Icon(Icons.cloud_upload),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: const Icon(Icons.group_outlined), label: 'Community'),
          BottomNavigationBarItem(
              icon: const Icon(Icons.favorite_border), label: 'Favorites'),
          BottomNavigationBarItem(
              icon: const Icon(Icons.shopping_cart_outlined),
              label: 'Shopping'),
        ],
      ),
    );
  }
}
