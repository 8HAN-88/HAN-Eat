import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import 'feed_service.dart';

/// Сервис бизнес-правил для ленты (в стиле VK)
/// Реализует ограничения и оптимизацию для улучшения UX
class FeedBusinessRulesService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Конфигурация бизнес-правил (можно вынести в настройки)
  static const _config = {
    'maxAdsPer10Posts': 1, // Максимум 1 реклама на 10 постов
    'maxSameAuthorInRow': 1, // Максимум 1 пост от автора подряд
    'authorSpacing': 4, // Минимум 4 поста между постами одного автора
    'minFreshPostsPercent': 0.25, // Минимум 25% свежих постов (< 12 часов)
    'maxSameTopicInRow': 3, // Максимум 3 поста одной темы подряд
    'recommendationsPercent': 0.3, // 30% рекомендаций в ленте
    'subscriptionBoostHours': 24, // Boost для подписок, если не видели > 24ч
  };

  /// Применить все бизнес-правила к ленте
  static Future<List<Post>> applyBusinessRules(
    List<Post> rankedPosts,
    String userId, {
    int targetLength = 50,
  }) async {
    if (rankedPosts.isEmpty) return rankedPosts;

    // 1. Разделяем на категории
    final regularPosts = <Post>[];
    final adPosts = <Post>[];
    final freshPosts = <Post>[];
    final now = DateTime.now();

    for (final post in rankedPosts) {
      if (post.isAd || post.isPromoted) {
        adPosts.add(post);
      } else {
        regularPosts.add(post);
        // Свежие посты (< 12 часов)
        if (now.difference(post.createdAt).inHours < 12) {
          freshPosts.add(post);
        }
      }
    }

    // 2. Обеспечиваем минимальную свежесть
    final minFreshCount = (targetLength * _config['minFreshPostsPercent']!).ceil();
    final freshInResult = <Post>[];
    final otherPosts = <Post>[];

    for (final post in regularPosts) {
      if (freshPosts.contains(post) && freshInResult.length < minFreshCount) {
        freshInResult.add(post);
      } else {
        otherPosts.add(post);
      }
    }

    // 3. Применяем ограничения к обычным постам
    final processedRegular = _applyAuthorSpacing(freshInResult + otherPosts);
    final processedRegularWithTopics = _applyTopicDiversity(processedRegular);

    // 4. Вставляем рекламу по правилам
    final resultWithAds = _insertAds(
      processedRegularWithTopics,
      adPosts,
      userId,
      targetLength: targetLength,
    );

    // 5. Применяем smoothing для подписок
    final withSubscriptionBoost = await _applySubscriptionSmoothing(
      resultWithAds,
      userId,
    );

    // 6. Учитываем негативные сигналы
    final withNegativeFeedback = await _applyNegativeFeedback(
      withSubscriptionBoost,
      userId,
    );

    // 7. Защита от эксплойтов
    final finalResult = _applyAntiExploit(withNegativeFeedback);

    return finalResult.take(targetLength).toList();
  }

  /// Правило 1: Ограничение рекламы (не более 1 на 10-12 постов)
  static List<Post> _insertAds(
    List<Post> regularPosts,
    List<Post> adCandidates,
    String userId, {
    required int targetLength,
  }) {
    if (adCandidates.isEmpty) return regularPosts;

    final result = <Post>[];
    final maxAds = (targetLength / 10).ceil();
    int adCount = 0;
    int regularIndex = 0;

    for (int i = 0; i < targetLength && regularIndex < regularPosts.length; i++) {
      // Вставляем рекламу каждые 10-12 постов
      if (adCount < maxAds && i > 0 && i % 10 == 0) {
        // Находим подходящую рекламу (можно добавить таргетинг)
        if (adCandidates.isNotEmpty) {
          final ad = adCandidates.removeAt(0);
          result.add(ad);
          adCount++;
          continue;
        }
      }

      if (regularIndex < regularPosts.length) {
        result.add(regularPosts[regularIndex]);
        regularIndex++;
      }
    }

    // Добавляем оставшиеся обычные посты
    while (regularIndex < regularPosts.length && result.length < targetLength) {
      result.add(regularPosts[regularIndex]);
      regularIndex++;
    }

    return result;
  }

  /// Правило 2: Ограничение спама от одного автора
  static List<Post> _applyAuthorSpacing(List<Post> posts) {
    final result = <Post>[];
    final authorPositions = <String, int>{}; // Последняя позиция автора
    final spacing = _config['authorSpacing']!;

    for (int i = 0; i < posts.length; i++) {
      final post = posts[i];
      final authorId = post.authorId ?? '';
      final lastPosition = authorPositions[authorId] ?? -spacing;

      // Если прошло достаточно постов с последнего поста этого автора
      if (result.length - lastPosition >= spacing) {
        result.add(post);
        authorPositions[authorId] = result.length - 1;
      } else {
        // Пытаемся найти замену дальше в списке
        bool found = false;
        for (int j = i + 1; j < posts.length && j < i + 10; j++) {
          final candidate = posts[j];
          final candidateAuthorId = candidate.authorId ?? '';
          final candidateLastPos = authorPositions[candidateAuthorId] ?? -spacing;
          if (result.length - candidateLastPos >= spacing) {
            // Меняем местами
            final temp = posts[i];
            posts[i] = candidate;
            posts[j] = temp;
            result.add(candidate);
            authorPositions[candidateAuthorId] = result.length - 1;
            found = true;
            break;
          }
        }
        if (!found) {
          // Если не нашли замену, пропускаем этот пост
          continue;
        }
      }
    }

    return result;
  }

  /// Правило 4: Контентная диверсификация (не более 3 одинаковых тем подряд)
  static List<Post> _applyTopicDiversity(List<Post> posts) {
    if (posts.length < 3) return posts;

    final result = <Post>[];
    final maxSameTopic = _config['maxSameTopicInRow']!;

    for (int i = 0; i < posts.length; i++) {
      final post = posts[i];
      final topic = _getPostTopic(post);

      // Проверяем последние N постов
      if (result.length >= maxSameTopic) {
        final recentTopics = result
            .sublist(result.length - maxSameTopic.toInt())
            .map((p) => _getPostTopic(p))
            .toSet();

        if (recentTopics.length == 1 && recentTopics.contains(topic)) {
          // Ищем пост с другой темой
          bool found = false;
          for (int j = i + 1; j < posts.length && j < i + 10; j++) {
            final candidate = posts[j];
            final candidateTopic = _getPostTopic(candidate);
            if (candidateTopic != topic) {
              // Меняем местами
              final temp = posts[i];
              posts[i] = candidate;
              posts[j] = temp;
              result.add(candidate);
              found = true;
              break;
            }
          }
          if (!found) {
            // Если не нашли, пропускаем
            continue;
          }
        } else {
          result.add(post);
        }
      } else {
        result.add(post);
      }
    }

    return result;
  }

  /// Получить тему поста (упрощенная версия)
  static String _getPostTopic(Post post) {
    // Можно использовать теги, категории, или ML-классификацию
    if (post.tags != null && post.tags!.isNotEmpty) {
      return post.tags!.first.toLowerCase();
    }
    // Fallback на тип поста
    return post.type;
  }

  /// Правило 5: Smoothing по авторам и группам (подписки)
  static Future<List<Post>> _applySubscriptionSmoothing(
    List<Post> posts,
    String userId,
  ) async {
    try {
      // Получаем список подписок
      final followingSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('following')
          .get();

      if (followingSnapshot.docs.isEmpty) return posts;

      final followingIds = followingSnapshot.docs.map((doc) => doc.id).toSet();
      final boostHours = _config['subscriptionBoostHours']!;
      final now = DateTime.now();

      // Проверяем, когда последний раз видели посты от каждого автора
      final authorLastSeen = <String, DateTime>{};
      for (final post in posts) {
        final authorId = post.authorId ?? '';
        if (followingIds.contains(authorId)) {
          final lastSeen = authorLastSeen[authorId];
          if (lastSeen == null ||
              now.difference(lastSeen).inHours > boostHours) {
            // Даем boost - перемещаем пост выше
            final index = posts.indexOf(post);
            if (index > 0) {
              posts.removeAt(index);
              // Вставляем ближе к началу (но не в самое начало)
              final insertIndex = (index * 0.3).ceil().clamp(0, posts.length);
              posts.insert(insertIndex, post);
            }
            authorLastSeen[authorId] = now;
          }
        }
      }
    } catch (e) {
      // Игнорируем ошибки
    }

    return posts;
  }

  /// Правило 7: Учет негативных сигналов (hide/report)
  static Future<List<Post>> _applyNegativeFeedback(
    List<Post> posts,
    String userId,
  ) async {
    try {
      // Получаем скрытые посты
      final hiddenSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('hiddenPosts')
          .get();

      final hiddenPostIds = hiddenSnapshot.docs.map((doc) => doc.id).toSet();

      // Получаем авторов скрытых постов из самих постов
      final hiddenAuthors = <String>{};
      for (final postId in hiddenPostIds) {
        try {
          final post = posts.firstWhere((p) => p.id == postId);
          final authorId = post.authorId ?? '';
          if (authorId.isNotEmpty) {
            hiddenAuthors.add(authorId);
          }
        } catch (_) {
          // Пост не найден в текущей ленте, пропускаем
        }
      }

      // Получаем жалобы
      final reportsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('reportedPosts')
          .get();

      final reportedPostIds = reportsSnapshot.docs.map((doc) => doc.id).toSet();
      final reportedAuthors = <String>{};
      for (final postId in reportedPostIds) {
        try {
          final post = posts.firstWhere((p) => p.id == postId);
          final authorId = post.authorId ?? '';
          if (authorId.isNotEmpty) {
            reportedAuthors.add(authorId);
          }
        } catch (_) {
          // Пост не найден в текущей ленте, пропускаем
        }
      }

      // Получаем информацию о подписках для авторов жалоб
      final followingChecks = <String, bool>{};
      for (final authorId in reportedAuthors) {
        try {
          final isFollowing = await _firestore
              .collection('users')
              .doc(userId)
              .collection('following')
              .doc(authorId)
              .get();
          followingChecks[authorId] = isFollowing.exists;
        } catch (_) {
          followingChecks[authorId] = false;
        }
      }

      // Фильтруем посты
      final filtered = posts.where((post) {
        // Убираем скрытые посты
        if (hiddenPostIds.contains(post.id)) return false;

        // Убираем жалобы
        if (reportedPostIds.contains(post.id)) return false;

        // Штраф за авторов скрытых постов (убираем на 24-48 часов)
        final authorId = post.authorId ?? '';
        if (hiddenAuthors.contains(authorId)) {
          // Ищем последний скрытый пост от этого автора
          DateTime? lastHiddenTime;
          for (final doc in hiddenSnapshot.docs) {
            try {
              final hiddenPost = posts.firstWhere((p) => p.id == doc.id);
              final hiddenAuthorId = hiddenPost.authorId ?? '';
              if (hiddenAuthorId == authorId) {
                final hiddenTime = doc.data()['createdAt'] as Timestamp?;
                if (hiddenTime != null) {
                  final hiddenDate = hiddenTime.toDate();
                  if (lastHiddenTime == null || hiddenDate.isAfter(lastHiddenTime)) {
                    lastHiddenTime = hiddenDate;
                  }
                }
              }
            } catch (_) {
              // Пост не найден, пропускаем
            }
          }
          if (lastHiddenTime != null) {
            final hoursSinceHidden = DateTime.now().difference(lastHiddenTime).inHours;
            if (hoursSinceHidden < 48) return false;
          }
        }

        // Штраф за авторов жалоб (убираем минимум на неделю)
        if (reportedAuthors.contains(authorId)) {
          // Проверяем, подписан ли пользователь (используем предварительно загруженные данные)
          final isFollowing = followingChecks[authorId] ?? false;
          if (!isFollowing) {
            // Если не подписан - убираем минимум на неделю
            return false;
          }
        }

        return true;
      }).toList();

      return filtered;
    } catch (e) {
      return posts;
    }
  }

  /// Правило 9: Анти-эксплойт защита
  static List<Post> _applyAntiExploit(List<Post> posts) {
    return posts.where((post) {
      // Проверка на подозрительную активность
      final reactions = post.reactions;
      final totalEngagement = reactions.likes + reactions.comments + reactions.shares;

      // Если очень много лайков, но мало комментариев и репостов - подозрительно
      if (reactions.likes > 1000 && reactions.comments < 10 && reactions.shares < 5) {
        // Можно добавить более сложную логику проверки
        // Пока просто пропускаем такие посты в рекомендациях
        return false;
      }

      // Проверка на слишком быстрый рост (возможная накрутка)
      final postAge = DateTime.now().difference(post.createdAt).inHours;
      if (postAge < 1 && totalEngagement > 500) {
        // Подозрительно много взаимодействий за короткое время
        return false;
      }

      return true;
    }).toList();
  }
}

