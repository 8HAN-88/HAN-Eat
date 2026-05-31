import 'package:uuid/uuid.dart';

import '../models/ai_meal_plan.dart';
import '../models/meal_plan.dart';
import '../models/recipe_model.dart';
import 'api_service.dart';
import 'meal_plan_service.dart';
import 'product_analytics.dart';

/// Перенос AI-плана в локальный недельный календарь (Hive + Firestore).
class AiMealPlanCalendarBridge {
  static const _uuid = Uuid();

  static MealType mealTypeFromString(String value) {
    switch (value) {
      case 'breakfast':
        return MealType.breakfast;
      case 'lunch':
        return MealType.lunch;
      case 'dinner':
        return MealType.dinner;
      case 'snack':
        return MealType.snack;
      default:
        return MealType.lunch;
    }
  }

  static RecipeModel recipeFromMealBlock(AiMealBlock meal) {
    final recipeMeta = meal.recommendedRecipes.isNotEmpty
        ? meal.recommendedRecipes.first
        : null;
    return RecipeModel(
      id: recipeMeta?.id?.toString() ?? _uuid.v4(),
      title: meal.title,
      cookTime: recipeMeta?.cookTimeMin ?? 25,
      ingredients: meal.ingredients,
      steps: const ['Следуйте рекомендациям AI-плана питания.'],
      image: recipeMeta?.imageUrl,
      updatedAt: DateTime.now(),
      calories: meal.nutrition['calories'],
      proteinG: meal.nutrition['protein_g'],
      carbsG: meal.nutrition['carbs_g'],
      fatG: meal.nutrition['fat_g'],
    );
  }

  /// Добавляет все блюда плана в календарь. При [replaceExisting] удаляет записи на те же даты.
  static Future<int> applyToCalendar(
    AiMealPlan plan, {
    bool replaceExisting = true,
  }) async {
    if (replaceExisting) {
      await MealPlanService.instance.removeEntriesForDates(
        plan.days.map((d) => DateTime.parse(d.date)).toList(),
      );
    }

    var count = 0;
    for (final day in plan.days) {
      if (day.date.isEmpty) continue;
      final date = DateTime.tryParse(day.date);
      if (date == null) continue;
      for (final meal in day.meals) {
        await MealPlanService.instance.addRecipeToPlan(
          recipe: recipeFromMealBlock(meal),
          mealType: mealTypeFromString(meal.mealType),
          date: date,
        );
        count++;
      }
    }

    await ApiService.logMealPlanApplyCalendar(
      mealsAdded: count,
      durationDays: plan.durationDays,
    );
    await ProductAnalytics.logEvent(
      eventType: 'meal_plan_applied_to_calendar',
      metadata: {
        'meals_added': count,
        'duration_days': plan.durationDays,
      },
    );
    return count;
  }
}
