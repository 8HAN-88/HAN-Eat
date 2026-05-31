import '../models/ai_meal_plan.dart';
import 'ai_meal_plan_calendar_bridge.dart';
import 'api_service.dart';
import 'nutrition_prefs_service.dart';
import 'product_analytics.dart';

class AiMealPlanService {
  AiMealPlanService._();
  static final AiMealPlanService instance = AiMealPlanService._();

  AiMealPlan? _activePlan;
  MealPlanLimits? _limits;

  AiMealPlan? get activePlan => _activePlan;
  MealPlanLimits? get limits => _limits;

  /// Загрузить последний сохранённый план с сервера (если есть).
  Future<AiMealPlan?> loadLatestSaved() async {
    try {
      final json = await ApiService.getLatestMealPlan();
      if (json == null) return null;
      _activePlan = AiMealPlan.fromJson(json);
      return _activePlan;
    } catch (_) {
      return null;
    }
  }

  Future<MealPlanLimits> fetchLimits() async {
    final json = await ApiService.getMealPlanLimits();
    _limits = MealPlanLimits.fromJson(json);
    return _limits!;
  }

  int _variationSeed() => DateTime.now().millisecondsSinceEpoch;

  Future<AiMealPlan> generate({required int durationDays}) async {
    final prefs = await NutritionPrefsService.loadForMealPlan();
    final json = await ApiService.generateMealPlan(
      durationDays: durationDays,
      preferences: prefs,
      variationSeed: _variationSeed(),
    );
    _activePlan = AiMealPlan.fromJson(json);
    await ProductAnalytics.logEvent(
      eventType: 'meal_plan_generated',
      metadata: {'duration_days': durationDays},
    );
    return _activePlan!;
  }

  Future<AiMealPlan> regenerate({
    required String scope,
    int dayIndex = 0,
    int mealIndex = 0,
    String? modifier,
  }) async {
    final plan = _activePlan;
    if (plan == null) {
      throw StateError('Нет активного плана');
    }
    final prefs = await NutritionPrefsService.loadForMealPlan();
    final json = await ApiService.regenerateMealPlan(
      plan: plan.toJson(),
      scope: scope,
      dayIndex: dayIndex,
      mealIndex: mealIndex,
      modifier: modifier,
      preferences: prefs,
      variationSeed: _variationSeed(),
    );
    _activePlan = AiMealPlan.fromJson(json);
    await ProductAnalytics.logEvent(
      eventType: 'meal_plan_regenerated',
      metadata: {
        'scope': scope,
        if (modifier != null) 'modifier': modifier,
      },
    );
    return _activePlan!;
  }

  Future<int> applyActivePlanToCalendar({bool replaceExisting = true}) async {
    final plan = _activePlan;
    if (plan == null) throw StateError('Нет активного плана');
    return AiMealPlanCalendarBridge.applyToCalendar(
      plan,
      replaceExisting: replaceExisting,
    );
  }

  Future<List<Map<String, dynamic>>> listSaved({int limit = 10}) async {
    return ApiService.listSavedMealPlans(limit: limit);
  }

  Future<AiMealPlan?> loadSavedByPlanId(String planId) async {
    final json = await ApiService.getSavedMealPlanById(planId);
    if (json == null) return null;
    _activePlan = AiMealPlan.fromJson(json);
    return _activePlan;
  }

  void setActivePlan(AiMealPlan plan) => _activePlan = plan;

  void clear() => _activePlan = null;
}
