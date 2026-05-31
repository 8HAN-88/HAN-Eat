// Сервис для работы с уведомлениями
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'auth_service.dart';
import 'server_config.dart';

class NotificationService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static Future<http.Response> _authorizedGet(Uri uri) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    var response = await http.get(uri, headers: _headers(token));
    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.get(uri, headers: _headers(token));
    }
    return response;
  }

  static Future<http.Response> _authorizedPut(Uri uri, {String? body}) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    var response = await http.put(
      uri,
      headers: _headers(token),
      body: body,
    );
    if (response.statusCode == 401) {
      token = await AuthService.refreshToken();
      response = await http.put(
        uri,
        headers: _headers(token),
        body: body,
      );
    }
    return response;
  }

  // Singleton instance
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localPluginReady = false;

  static const AndroidNotificationChannel _mealChannel =
      AndroidNotificationChannel(
    'meal_reminders',
    'Напоминания о еде',
    description: 'Локальные напоминания по плану питания',
    importance: Importance.defaultImportance,
  );

  static const AndroidNotificationChannel _pushChannel =
      AndroidNotificationChannel(
    'han_push',
    'Push-уведомления',
    description: 'Лайки, комментарии, каналы и подписка',
    importance: Importance.high,
  );

  static void Function(Map<String, dynamic> data)? _onPushPayloadTap;

  /// Локальные уведомления (напоминания о еде + foreground push) на iOS/Android.
  static Future<void> init({
    void Function(Map<String, dynamic> data)? onPushPayloadTap,
  }) async {
    if (kIsWeb) return;
    if (_localPluginReady) return;
    _onPushPayloadTap = onPushPayloadTap;
    try {
      tz_data.initializeTimeZones();
      _configureDeviceLocalTimezone();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            _onPushPayloadTap?.call(
              data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
            );
          } catch (e) {
            debugPrint('NotificationService tap payload parse: $e');
          }
        },
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_mealChannel);
      await androidPlugin?.createNotificationChannel(_pushChannel);
      _localPluginReady = true;
    } catch (e, st) {
      debugPrint('NotificationService.init local plugin: $e\n$st');
    }
  }

  /// Показать push в шторке, когда приложение на переднем плане (FCM onMessage).
  static Future<void> showForegroundPush({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (kIsWeb || !_localPluginReady) return;
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) return;
    try {
      final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
      final payload = data != null && data.isNotEmpty
          ? jsonEncode(data.map((k, v) => MapEntry(k, v?.toString() ?? '')))
          : null;
      await _localNotifications.show(
        id: id,
        title: t.isNotEmpty ? t : 'H.A.N. Eat',
        body: b.isNotEmpty ? b : t,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _pushChannel.id,
            _pushChannel.name,
            channelDescription: _pushChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e, st) {
      debugPrint('NotificationService.showForegroundPush: $e\n$st');
    }
  }

  int _androidNotificationId(String id) {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed.abs() % 2147483647;
    return id.hashCode.abs() % 2147483647;
  }

  Future<void> cancelNotification(String id) async {
    if (kIsWeb || !_localPluginReady) return;
    try {
      await _localNotifications.cancel(id: _androidNotificationId(id));
    } catch (e) {
      debugPrint('NotificationService.cancelNotification: $e');
    }
  }

  static void _configureDeviceLocalTimezone() {
    try {
      final offset = DateTime.now().timeZoneOffset;
      final totalMinutes = offset.inMinutes;
      final hours = totalMinutes ~/ 60;
      final remainder = totalMinutes.abs() % 60;
      if (remainder != 0) {
        tz.setLocalLocation(tz.UTC);
        return;
      }
      // Etc/GMT знак инвертирован: UTC+3 → Etc/GMT-3
      final sign = hours >= 0 ? '-' : '+';
      final absH = hours.abs();
      tz.setLocalLocation(tz.getLocation('Etc/GMT$sign$absH'));
    } catch (e) {
      debugPrint('NotificationService timezone: $e');
      tz.setLocalLocation(tz.UTC);
    }
  }

  static tz.TZDateTime _localScheduledTime(DateTime scheduledTime) {
    return tz.TZDateTime(
      tz.local,
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      scheduledTime.hour,
      scheduledTime.minute,
      scheduledTime.second,
    );
  }

  Future<void> scheduleNotification({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (kIsWeb || !_localPluginReady) return;
    if (!scheduledTime.isAfter(DateTime.now())) return;
    try {
      final when = _localScheduledTime(scheduledTime);
      final androidDetails = AndroidNotificationDetails(
        _mealChannel.id,
        _mealChannel.name,
        channelDescription: _mealChannel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const iosDetails = DarwinNotificationDetails();
      await _localNotifications.zonedSchedule(
        id: _androidNotificationId(id),
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } catch (e, st) {
      debugPrint('NotificationService.scheduleNotification: $e\n$st');
    }
  }
  
  /// Получить список уведомлений
  static Future<NotificationsResponse> getNotifications({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final uri = Uri.parse('$baseUrl/notifications').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'unread_only': unreadOnly.toString(),
      },
    );

    final response = await _authorizedGet(uri);

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return NotificationsResponse.fromJson(data);
      } catch (e, st) {
        debugPrint('NotificationService.getNotifications parse error: $e\n$st');
        rethrow;
      }
    }
    final detail = _tryDetail(response.body);
    throw Exception(detail ?? 'Не удалось загрузить уведомления (${response.statusCode})');
  }
  
  /// Пометить уведомление как прочитанное/непрочитанное
  static Future<void> markAsRead({
    required int notificationId,
    bool read = true,
  }) async {
    final uri = Uri.parse('$baseUrl/notifications/$notificationId/read');
    final response = await _authorizedPut(
      uri,
      body: jsonEncode({'read': read}),
    );

    if (response.statusCode == 200) {
      return;
    }
    final detail = _tryDetail(response.body);
    throw Exception(detail ?? 'Не удалось обновить уведомление (${response.statusCode})');
  }
  
  /// Пометить все уведомления как прочитанные
  static Future<void> markAllAsRead() async {
    final uri = Uri.parse('$baseUrl/notifications/read-all');
    final response = await _authorizedPut(uri);

    if (response.statusCode == 200) {
      return;
    }
    final detail = _tryDetail(response.body);
    throw Exception(detail ?? 'Не удалось пометить все как прочитанные (${response.statusCode})');
  }
  
  /// Получить количество непрочитанных уведомлений
  static Future<int> getUnreadCount() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      return 0;
    }

    final uri = Uri.parse('$baseUrl/notifications/unread-count');
    try {
      final response = await _authorizedGet(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = data['unread_count'];
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        return int.tryParse('$raw') ?? 0;
      }
    } catch (e) {
      debugPrint('NotificationService.getUnreadCount: $e');
    }
    return 0;
  }

  static String? _tryDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final d = decoded['detail'];
        if (d is String) return d;
      }
    } catch (_) {}
    return null;
  }
}

class NotificationsResponse {
  final List<NotificationItem> notifications;
  final int unreadCount;
  final bool hasMore;
  
  NotificationsResponse({
    required this.notifications,
    required this.unreadCount,
    required this.hasMore,
  });
  
  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['notifications'];
    final list = raw is List<dynamic>
        ? raw
        : raw is List
            ? List<dynamic>.from(raw)
            : <dynamic>[];
    final uc = json['unread_count'];
    final unread = uc is int ? uc : (uc is num ? uc.toInt() : int.tryParse('$uc') ?? 0);
    final hm = json['has_more'];
    final hasMore = hm is bool ? hm : hm == true || hm == 'true';
    return NotificationsResponse(
      notifications: list
          .map((item) => NotificationItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      unreadCount: unread,
      hasMore: hasMore,
    );
  }
}

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String? body;
  final String? entityType;
  final int? entityId;
  final NotificationActor? actor;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;
  final Map<String, dynamic>? data;
  
  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.entityType,
    this.entityId,
    this.actor,
    required this.isRead,
    this.readAt,
    this.createdAt,
    this.data,
  });
  
  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int
        ? idRaw
        : (idRaw as num?)?.toInt() ?? int.tryParse('$idRaw') ?? 0;
    if (id == 0) {
      debugPrint('NotificationItem.fromJson: missing or invalid id in $json');
    }
    final entityRaw = json['entity_id'];
    int? entityId;
    if (entityRaw != null) {
      if (entityRaw is int) {
        entityId = entityRaw;
      } else if (entityRaw is num) {
        entityId = entityRaw.toInt();
      } else {
        entityId = int.tryParse('$entityRaw');
      }
    }
    return NotificationItem(
      id: id,
      type: '${json['type'] ?? 'system'}',
      title: '${json['title'] ?? ''}',
      body: json['body'] as String?,
      entityType: json['entity_type'] as String?,
      entityId: entityId,
      actor: NotificationActor.maybeFromJson(json['actor']),
      isRead: json['is_read'] == true,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      data: _asStringKeyedMap(json['data']),
    );
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}

class NotificationActor {
  final int id;
  final String name;
  final String? username;
  final String? avatarUrl;
  
  NotificationActor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });
  
  static NotificationActor? maybeFromJson(dynamic raw) {
    if (raw == null || raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : (idRaw as num?)?.toInt();
    if (id == null) return null;
    final name = (json['name'] as String?)?.trim();
    return NotificationActor(
      id: id,
      name: (name != null && name.isNotEmpty) ? name : 'Пользователь',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  factory NotificationActor.fromJson(Map<String, dynamic> json) {
    final n = (json['name'] as String?)?.trim();
    return NotificationActor(
      id: (json['id'] as num).toInt(),
      name: (n != null && n.isNotEmpty) ? n : 'Пользователь',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
