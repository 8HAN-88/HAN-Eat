import 'package:flutter/material.dart';

import '../services/feed_api_cache.dart';
import '../services/story_feed_cache.dart';
import '../widgets/post_card_skeleton.dart';

/// Оболочка как у Instagram на 3G: табы и скелет сразу, без ожидания чанка/API.
class StartupHomePlaceholder extends StatelessWidget {
  const StartupHomePlaceholder({super.key});

  static const _canvas = Color(0xFF0F1319);

  @override
  Widget build(BuildContext context) {
    final stories = StoryFeedCache.peek();
    final posts = FeedApiCache.peek(FeedCacheKeys.recommendations());
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: _canvas,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HanWe',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 108,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  children: [
                    for (var i = 0; i < (stories.isEmpty ? 4 : stories.length.clamp(1, 8)); i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF2A3140),
                                border: Border.all(
                                  color: const Color(0xFFFF6B35),
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 48,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A3140),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: posts.isEmpty
                    ? ListView(
                        children: const [
                          PostCardSkeleton(),
                          PostCardSkeleton(),
                          PostCardSkeleton(),
                        ],
                      )
                    : ListView(
                        children: const [
                          PostCardSkeleton(),
                          PostCardSkeleton(),
                        ],
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              label: 'Чаты',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              label: 'Мини-приложения',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
