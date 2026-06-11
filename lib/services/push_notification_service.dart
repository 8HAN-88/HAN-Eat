import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Сервис для работы с push уведомлениями (FCM)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_router.dart';
import '../app/router_keys.dart';
import '../models/chat_models.dart';
import '../features/chat/application/chat_realtime_signals.dart';
import '../features/chat/application/chats_hub_refresh_provider.dart';
import '../features/navigation/application/shell_chat_badge_refresh_provider.dart';
import '../features/notifications/application/unread_notifications_provider.dart';
import '../features/chat/application/active_chat_session.dart';
import 'notification_service.dart';
import 'user_service.dart';

enum PushRegistrationState {
  unknown,
  ok,
  permissionDenied,
  noToken,
  serverSyncFailed,
  firebaseUnavailable,
}

class PushRegistrationInfo {
  const PushRegistrationInfo({
    required this.state,
    required this.message,
  });

  final PushRegistrationState state;
  final String message;

  bool get isHealthy => state == PushRegistrationState.ok;
}

class PushNotificationService {
  /// Должен совпадать с ключом, который сбрасывается при выходе из аккаунта.
  static const String _fcmTokenKey = 'fcm_token';
  static const String _serverSyncedKey = 'fcm_server_synced';
  static FirebaseMessaging? _messaging;
  static bool _listenersAttached = false;
  static PushRegistrationInfo lastRegistrationInfo = const PushRegistrationInfo(
    state: PushRegistrationState.unknown,
    message: 'Статус push не проверен',
  );

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
    final route = data['route']?.toString();
    final type = data['type']?.toString() ?? '';
    if (route == 'chat' || type == 'message') {
      final conversationId = _parseId(data, 'conversation_id', 'conversationId') ??
          (data['entity_type']?.toString() == 'conversation'
              ? _parseId(data, 'entity_id')
              : null);
      if (conversationId != null) {
        final actorId = _parseId(data, 'actor_id', 'actorId');
        final peer = ChatUserBrief(
          id: actorId ?? 0,
          name: data['title']?.toString(),
        );
        router.push(
          ChatThreadRoute.pathForId(conversationId),
          extra: peer,
        );
        return;
      }
    }
    if (route == 'subscription') {
      router.push('/subscription');
      return;
    }
    final userId = _parseId(data, 'user_id', 'actor_id');
    if (userId != null) {
      router.push('/profile?userId=$userId');
      return;
    }
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

  static void _onForegroundChatMessage(Map<String, dynamic> data) {
    final route = data['route']?.toString();
    final type = data['type']?.toString() ?? '';
    if (route != 'chat' && type != 'message') return;

    ChatRealtimeSignals.instance.notifyNewMessage();

    final ctx = hanEatRootNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ProviderScope.containerOf(ctx)
          .read(chatsHubRefreshProvider.notifier)
          .state++;
      ProviderScope.containerOf(ctx)
          .read(shellChatBadgeRefreshProvider.notifier)
          .state++;
    } catch (e) {
      debugPrint('FCM: chats hub refresh failed: $e');
    }
  }

  static void _maybeForegroundNotification(RemoteMessage message) {
    final route = message.data['route']?.toString();
    final type = message.data['type']?.toString() ?? '';
    if (route == 'chat' || type == 'message') {
      final conversationId = _parseId(
            message.data,
            'conversation_id',
            'conversationId',
          ) ??
          (message.data['entity_type']?.toString() == 'conversation'
              ? _parseId(message.data, 'entity_id')
              : null);
      if (conversationId != null &&
          ActiveChatSession.instance.isOpen(conversationId)) {
        return;
      }
    }

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

  static void _setRegistrationInfo(PushRegistrationInfo info) {
    lastRegistrationInfo = info;
  }

  static Future<PushRegistrationInfo> getRegistrationInfo() async {
    if (Firebase.apps.isEmpty) {
      const info = PushRegistrationInfo(
        state: PushRegistrationState.firebaseUnavailable,
        message: 'Firebase не настроен — push недоступны',
      );
      _setRegistrationInfo(info);
      return info;
    }
    _messaging ??= FirebaseMessaging.instance;
    final settings = await _messaging!.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      const info = PushRegistrationInfo(
        state: PushRegistrationState.permissionDenied,
        message: 'Разрешите уведомления в настройках iPhone',
      );
      _setRegistrationInfo(info);
      return info;
    }
    final token = await _messaging!.getToken();
    if (token == null || token.isEmpty) {
      const info = PushRegistrationInfo(
        state: PushRegistrationState.noToken,
        message: 'Не удалось получить токен push — попробуйте позже',
      );
      _setRegistrationInfo(info);
      return info;
    }
    final prefs = await SharedPreferences.getInstance();
    final serverOk = prefs.getBool(_serverSyncedKey) ?? false;
    if (!serverOk) {
      const info = PushRegistrationInfo(
        state: PushRegistrationState.serverSyncFailed,
        message: 'Токен не отправлен на сервер — нажмите «Повторить»',
      );
      _setRegistrationInfo(info);
      return info;
    }
    const info = PushRegistrationInfo(
      state: PushRegistrationState.ok,
      message: 'Push-уведомления подключены',
    );
    _setRegistrationInfo(info);
    return info;
  }

  /// Запросить разрешение и зарегистрировать FCM (явное действие пользователя).
  static Future<bool> requestPermissionAndRegister() async {
    if (Firebase.apps.isEmpty) return false;
    _messaging ??= FirebaseMessaging.instance;
    _attachListenersIfNeeded();

    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    if (!mobile) return false;

    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      _setRegistrationInfo(const PushRegistrationInfo(
        state: PushRegistrationState.permissionDenied,
        message: 'Разрешите уведомления в настройках iPhone',
      ));
      return false;
    }

    await _waitForApnsIfNeeded();
    await _updateFCMToken(force: true);
    return lastRegistrationInfo.isHealthy;
  }

  static Future<void> _waitForApnsIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      final apns = await _messaging!.getAPNSToken();
      if (apns != null) return;
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  static void _attachListenersIfNeeded() {
    if (_listenersAttached || _messaging == null) return;
    _listenersAttached = true;

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
      _onForegroundChatMessage(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('onMessageOpenedApp: ${message.data}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateFromPushData(message.data);
      });
    });

    _messaging!.onTokenRefresh.listen((String newToken) {
      debugPrint('FCM Token refreshed: $newToken');
      _updateFCMToken(newToken: newToken);
    });
  }

  /// Инициализировать Firebase Messaging
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('PushNotificationService: Firebase not ready, skip');
        _setRegistrationInfo(const PushRegistrationInfo(
          state: PushRegistrationState.firebaseUnavailable,
          message: 'Firebase не настроен — push недоступны',
        ));
        return;
      }
      _messaging ??= FirebaseMessaging.instance;
      _attachListenersIfNeeded();

      final settings = await _messaging!.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _waitForApnsIfNeeded();
        await _updateFCMToken();
      } else {
        _setRegistrationInfo(const PushRegistrationInfo(
          state: PushRegistrationState.permissionDenied,
          message:
              'Включите push в «Настройки уведомлений» или после входа в аккаунт',
        ));
      }

      final RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('App opened from notification: ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigateFromPushData(initialMessage.data);
        });
      }
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging: $e');
    }
  }

  /// После входа — синхронизировать токен, если разрешение уже выдано.
  static Future<void> syncTokenAfterAuth() async {
    if (Firebase.apps.isEmpty) return;
    _messaging ??= FirebaseMessaging.instance;
    _attachListenersIfNeeded();

    final settings = await _messaging!.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _waitForApnsIfNeeded();
      await _updateFCMToken(force: true);
      return;
    }

    _setRegistrationInfo(const PushRegistrationInfo(
      state: PushRegistrationState.permissionDenied,
      message: 'Разрешите push в «Настройки уведомлений»',
    ));
  }

  /// Обновить FCM токен на сервере
  static Future<void> _updateFCMToken({String? newToken, bool force = false}) async {
    try {
      final token = newToken ?? await _messaging?.getToken();
      if (token == null) {
        debugPrint('No FCM token available');
        _setRegistrationInfo(const PushRegistrationInfo(
          state: PushRegistrationState.noToken,
          message: 'Не удалось получить токен push',
        ));
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_fcmTokenKey);

      if (oldToken != token) {
        await prefs.setString(_fcmTokenKey, token);
      }

      final needServerUpdate = force || oldToken != token;
      if (!needServerUpdate) {
        final serverOk = prefs.getBool(_serverSyncedKey) ?? false;
        if (serverOk) {
          _setRegistrationInfo(const PushRegistrationInfo(
            state: PushRegistrationState.ok,
            message: 'Push-уведомления подключены',
          ));
        }
        return;
      }

      try {
        await UserService.updateProfile(fcmToken: token);
        await prefs.setBool(_serverSyncedKey, true);
        debugPrint('FCM token updated on server (force=$force)');
        _setRegistrationInfo(const PushRegistrationInfo(
          state: PushRegistrationState.ok,
          message: 'Push-уведомления подключены',
        ));
      } catch (e) {
        await prefs.setBool(_serverSyncedKey, false);
        debugPrint(
          'FCM: не удалось отправить токен (часто нет сессии до входа): $e',
        );
        _setRegistrationInfo(const PushRegistrationInfo(
          state: PushRegistrationState.serverSyncFailed,
          message: 'Токен не отправлен на сервер',
        ));
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
      _setRegistrationInfo(const PushRegistrationInfo(
        state: PushRegistrationState.noToken,
        message: 'Ошибка регистрации push',
      ));
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
      await prefs.remove(_serverSyncedKey);
      debugPrint('FCM token deleted');
    } catch (e) {
      debugPrint('Error deleting FCM token: $e');
    }
  }
}

