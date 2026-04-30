import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:uuid/uuid.dart';

import '../models/meal_plan.dart';
import '../models/recipe_model.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class MealPlanService {
  static MealPlanService? _instance;
  static MealPlanService get instance {
    if (_instance == null) {
      throw Exception(
          'MealPlanService not initialized. Call MealPlanService.init() first.');
    }
    return _instance!;
  }

  static const String _boxName = 'meal_plans';
  late final Box<dynamic> _box;

  final ValueNotifier<List<MealPlanEntry>> allEntries = ValueNotifier([]);
  final ValueNotifier<List<MealPlanEntry>> upcomingMeals = ValueNotifier([]);

  StreamSubscription<User?>? _authSub;
  Timer? _upcomingMealsTimer;

  final _uuid = const Uuid();

  MealPlanService._internal(this._box) {
    _loadFromBox();
    _updateUpcomingMeals();
    // Обновляем предстоящие приемы пищи каждую минуту
    _upcomingMealsTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateUpcomingMeals(),
    );
  }

  static Future<void> init({bool startAuthSync = true}) async {
    if (_instance != null) {
      try {
        await _instance!._disposeInternal();
      } catch (_) {}
    }
    final box = await Hive.openBox<dynamic>(_boxName);
    _instance = MealPlanService._internal(box);
    if (startAuthSync && AuthService.isInitialized) {
      await _instance!._startAuthSync();
    }
  }

  Future<void> _startAuthSync() async {
    if (_authSub != null) return;
    try {
      _authSub = AuthService.instance.authStateChanges().listen((user) async {
        if (user != null) {
          await _syncFromCloud(user.uid);
        }
      });
      final current = AuthService.instance.currentUser;
      if (current != null) {
        await _syncFromCloud(current.uid);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MealPlanService _startAuthSync failed: $e');
    }
  }

  Future<void> _syncFromCloud(String uid) async {
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meal_plans');
      final snapshot = await col.get();
      
      // Загружаем из облака
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final entry = MealPlanEntry.fromJson(data);
        await _addToBox(entry);
      }
      
      _loadFromBox();
      
      // Отправляем локальные изменения в облако
      for (final entry in allEntries.value) {
        await _syncToCloud(entry, uid);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MealPlan sync error: $e');
    }
  }

  Future<void> _syncToCloud(MealPlanEntry entry, String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meal_plans')
          .doc(entry.id)
          .set(entry.toJson());
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to sync meal plan entry to cloud: $e');
    }
  }

  void _loadFromBox() {
    final entries = <MealPlanEntry>[];
    for (final key in _box.keys) {
      try {
        final value = _box.get(key);
        Map<String, dynamic> json;
        if (value is String) {
          // Если сохранено как JSON строка (через адаптер)
          json = jsonDecode(value) as Map<String, dynamic>;
        } else if (value is Map) {
          // Если сохранено напрямую как Map
          json = Map<String, dynamic>.from(value);
        } else {
          continue;
        }
        final entry = MealPlanEntry.fromJson(json);
        entries.add(entry);
      } catch (e) {
        if (kDebugMode) debugPrint('Error loading meal plan entry: $e');
      }
    }
    allEntries.value = entries;
  }

  List<MealPlanEntry> _getEntriesForDate(DateTime date) {
    return allEntries.value.where((entry) {
      return _isSameDate(entry.date, date);
    }).toList();
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _updateUpcomingMeals() {
    final now = DateTime.now();
    final upcoming = allEntries.value.where((entry) {
      return entry.date.isAfter(now) || _isSameDate(entry.date, now);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    upcomingMeals.value = upcoming.take(10).toList();
  }

  Future<void> addRecipeToPlan({
    required RecipeModel recipe,
    required MealType mealType,
    required DateTime date,
    int servings = 1,
  }) async {
    final entry = MealPlanEntry(
      id: _uuid.v4(),
      recipe: recipe,
      mealType: mealType,
      date: date,
      servings: servings,
    );

    await _addToBox(entry);
    _loadFromBox();
    _updateUpcomingMeals();

    // Синхронизация и напоминание — в фоне, чтобы не блокировать UI
    if (AuthService.isInitialized && AuthService.instance.currentUser != null) {
      final uid = AuthService.instance.currentUser!.uid;
      _syncToCloud(entry, uid).catchError((e) {
        if (kDebugMode) debugPrint('MealPlanService sync to cloud: $e');
      });
    }
    _scheduleMealReminder(entry).catchError((e) {
      if (kDebugMode) debugPrint('MealPlanService schedule reminder: $e');
    });
  }

  Future<void> _addToBox(MealPlanEntry entry) async {
    // Сохраняем как JSON строку для совместимости с адаптером
    await _box.put(entry.id, jsonEncode(entry.toJson()));
  }

  Future<void> removeFromPlan(String entryId) async {
    await _box.delete(entryId);
    
    // Удаляем из облака
    if (AuthService.isInitialized && AuthService.instance.currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(AuthService.instance.currentUser!.uid)
            .collection('meal_plans')
            .doc(entryId)
            .delete();
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to delete meal plan from cloud: $e');
      }
    }
    
    _loadFromBox();
    _updateUpcomingMeals();
    
    // Отменяем напоминание
    await NotificationService.instance.cancelNotification(
      _getNotificationId(entryId).toString(),
    );
  }

  Future<void> updateEntry(MealPlanEntry entry) async {
    await _addToBox(entry);
    
    // Синхронизация с облаком
    if (AuthService.isInitialized && AuthService.instance.currentUser != null) {
      await _syncToCloud(entry, AuthService.instance.currentUser!.uid);
    }
    
    _loadFromBox();
    _updateUpcomingMeals();
    
    // Обновляем напоминание
    await _scheduleMealReminder(entry);
  }

  DailyMealPlan getPlanForDate(DateTime date) {
    final entries = _getEntriesForDate(date);
    return DailyMealPlan(date: date, entries: entries);
  }

  List<MealPlanEntry> getUpcomingMealsForNextDays(int days) {
    final now = DateTime.now();
    final endDate = now.add(Duration(days: days));
    return allEntries.value
        .where((entry) => entry.date.isAfter(now) && entry.date.isBefore(endDate))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> clearAllPlans() async {
    await _box.clear();
    _loadFromBox();
    _updateUpcomingMeals();
    
    // Удаляем из облака
    if (AuthService.isInitialized && AuthService.instance.currentUser != null) {
      try {
        final col = FirebaseFirestore.instance
            .collection('users')
            .doc(AuthService.instance.currentUser!.uid)
            .collection('meal_plans');
        final snapshot = await col.get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to clear meal plans from cloud: $e');
      }
    }
  }

  Future<void> _scheduleMealReminder(MealPlanEntry entry) async {
    // Напоминание за 30 минут до приема пищи
    final reminderTime = entry.date.subtract(const Duration(minutes: 30));
    if (reminderTime.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleNotification(
        id: _getNotificationId(entry.id).toString(),
        title: 'Напоминание о ${entry.mealType.displayName}',
        body: 'Через 30 минут: ${entry.recipe.title}',
        scheduledTime: reminderTime,
      );
    }
  }

  int _getNotificationId(String entryId) {
    // Генерируем уникальный ID для уведомления на основе entryId
    return entryId.hashCode.abs() % 2147483647;
  }

  Future<void> _disposeInternal() async {
    try {
      await _authSub?.cancel();
    } catch (_) {}
    try {
      _upcomingMealsTimer?.cancel();
    } catch (_) {}
    try {
      await _box.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _disposeInternal();
    allEntries.dispose();
    upcomingMeals.dispose();
    _instance = null;
  }
}

