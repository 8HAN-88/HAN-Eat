/// Сервис для работы с push уведомлениями (FCM)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';

class PushNotificationService {
  static const String _fcmTokenKey = 'fcm_token';
  static FirebaseMessaging? _messaging;
  
  /// Инициализировать Firebase Messaging
  static Future<void> initialize() async {
    try {
      _messaging = FirebaseMessaging.instance;
      
      // Запрашиваем разрешение на уведомления (iOS)
      NotificationSettings settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted permission for notifications');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('User granted provisional permission');
      } else {
        print('User declined or has not accepted permission');
        return;
      }
      
      // Получаем FCM токен
      await _updateFCMToken();
      
      // Обработка уведомлений, когда приложение в foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');
        
        if (message.notification != null) {
          print('Message also contained a notification: ${message.notification}');
          // TODO: Показать локальное уведомление или обновить UI
        }
      });
      
      // Обработка уведомлений, когда приложение открыто из уведомления
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('A new onMessageOpenedApp event was published!');
        print('Message data: ${message.data}');
        // TODO: Навигация к соответствующему экрану
      });
      
      // Проверяем, было ли приложение открыто из уведомления
      RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        print('App opened from notification');
        print('Message data: ${initialMessage.data}');
        // TODO: Навигация к соответствующему экрану
      }
      
      // Обработка обновления токена
      _messaging!.onTokenRefresh.listen((String newToken) {
        print('FCM Token refreshed: $newToken');
        _updateFCMToken(newToken: newToken);
      });
      
    } catch (e) {
      print('Error initializing Firebase Messaging: $e');
    }
  }
  
  /// Обновить FCM токен на сервере
  static Future<void> _updateFCMToken({String? newToken}) async {
    try {
      final token = newToken ?? await _messaging?.getToken();
      if (token == null) {
        print('No FCM token available');
        return;
      }
      
      // Сохраняем токен локально
      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_fcmTokenKey);
      
      // Если токен изменился, обновляем на сервере
      if (oldToken != token) {
        await prefs.setString(_fcmTokenKey, token);
        
        // Отправляем токен на сервер
        try {
          await UserService.updateProfile(fcmToken: token);
          print('FCM token updated on server');
        } catch (e) {
          print('Failed to update FCM token on server: $e');
        }
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }
  
  /// Получить текущий FCM токен
  static Future<String?> getToken() async {
    try {
      return await _messaging?.getToken();
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }
  
  /// Подписаться на топик
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging?.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic: $e');
    }
  }
  
  /// Отписаться от топика
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging?.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic: $e');
    }
  }
  
  /// Удалить FCM токен (при выходе из аккаунта)
  static Future<void> deleteToken() async {
    try {
      await _messaging?.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fcmTokenKey);
      print('FCM token deleted');
    } catch (e) {
      print('Error deleting FCM token: $e');
    }
  }
}

