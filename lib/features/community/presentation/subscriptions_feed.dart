import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';
import 'reels_feed_screen.dart';

/// Лента видео от подписанных авторов
class SubscriptionsFeed extends StatefulWidget {
  const SubscriptionsFeed({super.key});

  @override
  State<SubscriptionsFeed> createState() => _SubscriptionsFeedState();
}

class _SubscriptionsFeedState extends State<SubscriptionsFeed> {
  List<String> _followingIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final currentUid = AuthService.instance.currentUser?.uid;
    if (currentUid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('following')
          .get();

      if (!mounted) return;

      setState(() {
        _followingIds = snapshot.docs.map((doc) => doc.id).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = AuthService.instance.currentUser?.uid;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (currentUid == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Войдите, чтобы видеть видео от подписок',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_followingIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Подписки',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Подпишитесь на авторов, чтобы видеть их видео здесь',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Показываем видео от подписанных авторов
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('community_videos')
          .where('status', isEqualTo: 'published')
          .where('uploaderId', whereIn: _followingIds.length > 10 
              ? _followingIds.take(10).toList() // Firestore ограничение
              : _followingIds)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final videos = snapshot.data!.docs;
        if (videos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Пока нет новых видео',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Авторы, на которых вы подписаны, еще не опубликовали видео',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Используем ReelsFeedScreen с предзагруженными видео
        return _SubscriptionsReelsFeed(videos: videos);
      },
    );
  }
}

/// Адаптированная версия ReelsFeed для подписок
class _SubscriptionsReelsFeed extends StatefulWidget {
  final List<DocumentSnapshot> videos;

  const _SubscriptionsReelsFeed({required this.videos});

  @override
  State<_SubscriptionsReelsFeed> createState() => _SubscriptionsReelsFeedState();
}

class _SubscriptionsReelsFeedState extends State<_SubscriptionsReelsFeed> {
  @override
  Widget build(BuildContext context) {
    // Для упрощения используем список, но можно адаптировать PageView из ReelsFeedScreen
    return ListView.builder(
      itemCount: widget.videos.length,
      itemBuilder: (context, index) {
        final doc = widget.videos[index];
        final data = doc.data() as Map<String, dynamic>;
        final title = data['title'] as String? ?? 'Без названия';
        final author = data['uploaderId'] as String? ?? 'Неизвестный автор';
        
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            leading: const Icon(Icons.play_circle_fill),
            title: Text(title),
            subtitle: Text('От $author'),
            onTap: () {
              // TODO: Navigate to video
            },
          ),
        );
      },
    );
  }
}

