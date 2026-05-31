import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/legacy_firestore_config.dart';
import 'auth_service.dart';

class NotificationSettings {
  final bool likes;
  final bool comments;
  final bool uploads;

  NotificationSettings({
    required this.likes,
    required this.comments,
    required this.uploads,
  });

  NotificationSettings copyWith({bool? likes, bool? comments, bool? uploads}) {
    return NotificationSettings(
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      uploads: uploads ?? this.uploads,
    );
  }

  Map<String, dynamic> toMap() => {
        'likes': likes,
        'comments': comments,
        'uploads': uploads,
      };

  factory NotificationSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      return NotificationSettings(likes: true, comments: true, uploads: true);
    }
    return NotificationSettings(
      likes: m['likes'] as bool? ?? true,
      comments: m['comments'] as bool? ?? true,
      uploads: m['uploads'] as bool? ?? true,
    );
  }

  String toJson() => json.encode(toMap());
  factory NotificationSettings.fromJson(String s) =>
      NotificationSettings.fromMap(json.decode(s) as Map<String, dynamic>);
}

class NotificationSettingsService {
  static NotificationSettingsService? _instance;
  static bool _initialized = false;

  static const _prefsKey = 'notification_settings_v1';
  final ValueNotifier<NotificationSettings> settings = ValueNotifier(
      NotificationSettings(likes: true, comments: true, uploads: true));
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void Function(User?)? _onSessionChanged;

  NotificationSettingsService._internal();

  static Future<void> init() async {
    if (_initialized) return;
    _instance = NotificationSettingsService._internal();
    await _instance!._start();
    _initialized = true;
  }

  // Non-nullable getter used across the codebase.
  static NotificationSettingsService get instance {
    if (_instance == null) {
      throw Exception(
          'NotificationSettingsService not initialized. Call NotificationSettingsService.init() in bootstrap.');
    }
    return _instance!;
  }

  static bool get isInitialized => _initialized;

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    // load local prefs if exist
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        settings.value = NotificationSettings.fromJson(raw);
      } catch (_) {}
    }

    _onSessionChanged = (User? user) {
      if (user != null) {
        unawaited(_loadAndMergeRemote(user.uid));
      }
    };
    AuthService.registerSessionListener(_onSessionChanged!);

    // Уже залогинен — подтягиваем Firestore после старта UI, чтобы не конкурировать с вторым процессом
    // и не блокировать первый кадр (меню / рекомендации).
    final current = AuthService.instance.currentUser;
    if (current != null) {
      Future<void>.delayed(const Duration(milliseconds: 800), () async {
        try {
          await _loadAndMergeRemote(current.uid);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('NotificationSettings deferred remote load: $e');
          }
        }
      });
    }
  }

  Future<void> _loadAndMergeRemote(String uid) async {
    if (LegacyFirestoreConfig.disabled) return;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      if (doc.exists) {
        final remote = NotificationSettings.fromMap(doc.data());
        // Merge: remote values override local
        settings.value = remote;
        // persist locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, settings.value.toJson());
      } else {
        // push local to remote
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('notifications')
            .set(settings.value.toMap());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationSettings load/merge failed: $e');
    }
  }

  Future<void> updateSettings(NotificationSettings newSettings) async {
    settings.value = newSettings;
    // persist locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, newSettings.toJson());

    // persist remote if user signed in
    final user = AuthService.instance.currentUser;
    if (LegacyFirestoreConfig.enabled && user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('notifications')
            .set(newSettings.toMap());
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to save notification settings remote: $e');
        }
      }
    }
  }

  // convenience
  bool allowsType(String? type) {
    if (type == null) return true;
    final t = type.toLowerCase();
    if (t == 'like' || t == 'likes') return settings.value.likes;
    if (t == 'comment' || t == 'comments') return settings.value.comments;
    if (t == 'upload' || t == 'uploads') return settings.value.uploads;
    return true;
  }

  void dispose() {
    if (_onSessionChanged != null) {
      AuthService.unregisterSessionListener(_onSessionChanged!);
      _onSessionChanged = null;
    }
    settings.dispose();
  }
}
