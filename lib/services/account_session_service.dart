import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'favorites_service.dart';
import 'ai_meal_plan_service.dart';
import 'meal_plan_service.dart';
import 'saved_posts_service.dart';
import 'user_service.dart';

/// Единая точка смены аккаунта: очистка кэшей и сигнал UI пересобраться.
class AccountSessionService {
  AccountSessionService._();

  /// Меняется при каждом входе/выходе/смене пользователя — ключ для вкладок.
  static final ValueNotifier<int> epoch = ValueNotifier(0);

  static int? _activeUserId;
  static int? get activeUserId => _activeUserId;

  /// При холодном старте — без очистки кэшей и без пересборки shell.
  static void restoreCachedUser(User? user) {
    _activeUserId = user?.id;
  }

  static final List<void Function(User?)> _listeners = [];

  static void registerListener(void Function(User?) listener) {
    _listeners.add(listener);
  }

  static void unregisterListener(void Function(User?) listener) {
    _listeners.remove(listener);
  }

  /// Вызывается из [AuthService] перед остальными session listeners.
  static Future<void> applySessionChange(User? user) async {
    final previousId = _activeUserId;
    final nextId = user?.id;
    final switchedAccount = previousId != null &&
        nextId != null &&
        previousId != nextId;
    final signedOut = user == null;
    final shouldPurgeLocalUserData = signedOut || switchedAccount;

    _activeUserId = nextId;

    if (shouldPurgeLocalUserData) {
      UserService.instance.profile.value = null;
      try {
        await SavedPostsService.clearLocalCache();
      } catch (e) {
        if (kDebugMode) debugPrint('AccountSession: saved posts clear: $e');
      }
      try {
        await FavoritesService.instance.clearLocalSession();
      } catch (e) {
        if (kDebugMode) debugPrint('AccountSession: favorites clear: $e');
      }
      try {
        await MealPlanService.instance.clearAllPlans();
      } catch (e) {
        if (kDebugMode) debugPrint('AccountSession: meal plan clear: $e');
      }
      AiMealPlanService.instance.clear();
    }

    AuthService.profileVersion.value++;
    epoch.value++;

    for (final listener in List<void Function(User?)>.from(_listeners)) {
      try {
        listener(user);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AccountSession listener error: $e\n$st');
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'AccountSession: user ${previousId ?? "—"} → ${nextId ?? "—"} '
        '(purge=$shouldPurgeLocalUserData, epoch=${epoch.value})',
      );
    }
  }
}
