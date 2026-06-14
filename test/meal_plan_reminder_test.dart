import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/meal_plan.dart';
import 'package:han_eat/models/recipe_model.dart';

void main() {
  test('mealDateTime uses distinct default hours per meal type', () {
    final day = DateTime(2026, 5, 27);
    final breakfast = MealPlanEntry(
      id: '1',
      recipe: RecipeModel(
        id: 'r1',
        title: 'Йогурт',
        cookTime: 5,
        ingredients: const [],
        steps: const [],
        updatedAt: DateTime.now(),
      ),
      mealType: MealType.breakfast,
      date: day,
    );
    final lunch = breakfast.copyWith(id: '2', mealType: MealType.lunch);
    final dinner = breakfast.copyWith(id: '3', mealType: MealType.dinner);

  // Helper duplicated from service for unit test (no Hive init).
    DateTime mealAt(MealPlanEntry e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final (h, m) = e.mealType.defaultTime;
      return DateTime(d.year, d.month, d.day, h, m);
    }

    final b = mealAt(breakfast);
    final l = mealAt(lunch);
    final d = mealAt(dinner);

    expect(b.hour, 8);
    expect(l.hour, 13);
    expect(d.hour, 19);
    expect(b, isNot(equals(l)));
    expect(l, isNot(equals(d)));
  });
}
