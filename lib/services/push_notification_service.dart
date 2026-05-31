import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Сервис для работы с push уведомлениями (FCM)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/router_keys.dart';
import '../features/notifications/application/unread_notifications_provider.dart';
import 'notification_service.dart';
import 'user_service.dart';

class PushNotificationService {
  /// Должен совпадать с ключом, который сбрасывается при выходе из аккаунта.
  static const String _fcmTokenKey = 'fcm_token';
  static FirebaseMessaging? _messaging;

  static int? _parseId(Map<String, dynamic> data, String a, [String? b]) {
    final v = data[a] ?? (b != null ? data[b] : null);
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  /// Навигация по `data` из FCM (ключи могут отличаться на бэкенде).
  static void navigateFromPushData(Map<String, dynamic> data) {
    final ctx = hanEatRootNavigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('FCM: navigate — нет root context');
      return;
    }
    final router = GoRouter.of(ctx);
    final postId = _parseId(data, 'post_id', 'postId');
    final channelId = _parseId(data, 'channel_id', 'channelId');

    if (channelId != null && postId != null) {
      router.push('/channel/$channelId/post/$postId');
      return;
    }
    if (postId != null) {
      router.push('/post/$postId');
      return;
    }
    if (channelId != null) {
      router.push('/channel/$channelId');
      return;
    }
    final userId = _parseId(data, 'user_id', 'actor_id');
    if (userId != null) {
      router.push('/profile?userId=$userId');
      return;
    }
    final route = data['route']?.toString();
    if (route == 'subscription') {
      router.push('/subscription');
      return;
    }
    final type = data['type']?.toString() ?? '';
    if (type.startsWith('subscription_')) {
      router.push('/subscription');
      return;
    }
    router.push('/notifications');
  }

  static void _refreshUnreadBadge() {
    final ctx = hanEatRootNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ProviderScope.containerOf(ctx)
          .read(unreadNotificationsCountProvider.notifier)
          .refresh();
    } catch (e) {
      debugPrint('FCM: refresh unread badge failed: $e');
    }
  }

  static void _maybeForegroundNotification(RemoteMessage message) {
    final title = message.notification?.title?.trim() ??
        message.data['title']?.toString().trim();
    final body = message.notification?.body?.trim() ??
        message.data['body']?.toString().trim();
    if ((title == null || title.isEmpty) &&
        (body == null || body.isEmpty)) {
      return;
    }
    NotificationService.showForegroundPush(
      title: title ?? 'H.A.N. Eat',
      body: body ?? '',
      data: message.data.isNotEmpty ? message.data : null,
    );
  }

  /// После входа / восстановления сессии — повторно отправить FCM на backend.
  static Future<void> syncTokenAfterAuth() async {
    await _updateFCMToken(force: true);
  }

  /// Инициализировать Firebase Messaging
  static Future<void> initialize() async {
    try {
      _messaging = FirebaseMessaging.instance;

      final mobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);

      if (mobile) {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('User granted permission for notifications');
        } else if (settings.authorizationStatus ==
            AuthorizationStatus.provisional) {
          debugPrint('User granted provisional permission');
        } else {
          debugPrint(
            'User declined or has not accepted permission — пропускаем FCM',
          );
          return;
        }
      } else {
        debugPrint(
          'Push: пропуск requestPermission на $defaultTargetPlatform (часто недоступно или запрещено)',
        );
      }

      await _updateFCMToken();
      
      // Обработка уведомлений, когда приложение в foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');
        if (message.notification != null) {
          debugPrint(
            'Message also contained a notification: ${message.notification}',
          );
        }
        _maybeForegroundNotification(message);
        _refreshUnreadBadge();
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('onMessageOpenedApp: ${message.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigateFromPushData(message.data);
        });
      });

      final RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('App opened from notification: ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigateFromPushData(initialMessage.data);
        });
      }
      
      // Обработка обновления токена
      _messaging!.onTokenRefresh.listen((String newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        _updateFCMToken(newToken: newToken);
      });
      
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging: $e');
    }
  }
  
  /// Обновить FCM токен на сервере
  static Future<void> _updateFCMToken({String? newToken, bool force = false}) async {
    try {
      final token = newToken ?? await _messaging?.getToken();
      if (token == null) {
        debugPrint('No FCM token available');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_fcmTokenKey);

      if (oldToken != token) {
        await prefs.setString(_fcmTokenKey, token);
      }

      final needServerUpdate = force || oldToken != token;
      if (!needServerUpdate) {
        return;
      }

      try {
        await UserService.updateProfile(fcmToken: token);
        debugPrint('FCM token updated on server (force=$force)');
      } catch (e) {
        debugPrint(
          'FCM: не удалось отправить токен (часто нет сессии до входа): $e',
        );
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }
  
  /// Получить текущий FCM токен
  static Future<String?> getToken() async {
    try {
      return await _messaging?.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }
  
  /// Подписаться на топик
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging?.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }
  
  /// Отписаться от топика
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging?.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }
  
  /// Удалить FCM токен (при выходе из аккаунта)
  static Future<void> deleteToken() async {
    try {
      await _messaging?.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fcmTokenKey);
      debugPrint('FCM token deleted');
    } catch (e) {
      debugPrint('Error deleting FCM token: $e');
    }
  }
}

