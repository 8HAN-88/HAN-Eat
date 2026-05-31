class AiMealPlanRecipe {
  const AiMealPlanRecipe({
    this.id,
    required this.title,
    this.imageUrl,
    this.calories,
    this.cookTimeMin,
  });

  final int? id;
  final String title;
  final String? imageUrl;
  final int? calories;
  final int? cookTimeMin;

  factory AiMealPlanRecipe.fromJson(Map<String, dynamic> json) {
    return AiMealPlanRecipe(
      id: (json['id'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      calories: (json['calories'] as num?)?.toInt(),
      cookTimeMin: (json['cook_time_min'] as num?)?.toInt(),
    );
  }
}

class AiMealBlock {
  const AiMealBlock({
    required this.mealType,
    required this.title,
    required this.guidance,
    required this.ingredients,
    required this.nutrition,
    this.recommendedRecipes = const [],
  });

  final String mealType;
  final String title;
  final String guidance;
  final List<String> ingredients;
  final Map<String, double> nutrition;
  final List<AiMealPlanRecipe> recommendedRecipes;

  String get mealTypeLabel {
    switch (mealType) {
      case 'breakfast':
        return 'Завтрак';
      case 'lunch':
        return 'Обед';
      case 'dinner':
        return 'Ужин';
      case 'snack':
        return 'Перекус';
      default:
        return mealType;
    }
  }

  factory AiMealBlock.fromJson(Map<String, dynamic> json) {
    final nut = json['nutrition'] as Map<String, dynamic>? ?? {};
    return AiMealBlock(
      mealType: json['meal_type'] as String? ?? 'lunch',
      title: json['title'] as String? ?? '',
      guidance: json['guidance'] as String? ?? '',
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      nutrition: nut.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
      ),
      recommendedRecipes: (json['recommended_recipes'] as List<dynamic>?)
              ?.map((e) => AiMealPlanRecipe.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AiDayPlan {
  const AiDayPlan({
    required this.date,
    required this.dayIndex,
    required this.meals,
    required this.dayTotals,
  });

  final String date;
  final int dayIndex;
  final List<AiMealBlock> meals;
  final Map<String, double> dayTotals;

  factory AiDayPlan.fromJson(Map<String, dynamic> json) {
    final totals = json['day_totals'] as Map<String, dynamic>? ?? {};
    return AiDayPlan(
      date: json['date'] as String? ?? '',
      dayIndex: (json['day_index'] as num?)?.toInt() ?? 0,
      meals: (json['meals'] as List<dynamic>?)
              ?.map((e) => AiMealBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dayTotals: totals.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
      ),
    );
  }
}

class AiShoppingItem {
  const AiShoppingItem({required this.name, this.quantity});

  final String name;
  final String? quantity;

  factory AiShoppingItem.fromJson(Map<String, dynamic> json) {
    return AiShoppingItem(
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as String?,
    );
  }
}

class AiShoppingCategory {
  const AiShoppingCategory({
    required this.id,
    required this.name,
    required this.items,
  });

  final String id;
  final String name;
  final List<AiShoppingItem> items;

  factory AiShoppingCategory.fromJson(Map<String, dynamic> json) {
    return AiShoppingCategory(
      id: json['id'] as String? ?? 'other',
      name: json['name'] as String? ?? 'Другое',
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => AiShoppingItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AiMealPlan {
  const AiMealPlan({
    required this.planId,
    required this.durationDays,
    required this.tier,
    required this.aiRecommendation,
    required this.nutritionStrategy,
    required this.days,
    required this.shoppingList,
    this.canRegenerateUnlimited = false,
    this.smartShopping = false,
    this.regenerationCount = 0,
  });

  final String planId;
  final int durationDays;
  final String tier;
  final String aiRecommendation;
  final Map<String, dynamic> nutritionStrategy;
  final List<AiDayPlan> days;
  final List<AiShoppingCategory> shoppingList;
  final bool canRegenerateUnlimited;
  final bool smartShopping;
  final int regenerationCount;

  factory AiMealPlan.fromJson(Map<String, dynamic> json) {
    final shop = json['shopping_list'] as Map<String, dynamic>? ?? {};
    return AiMealPlan(
      planId: json['plan_id'] as String? ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 3,
      tier: json['tier'] as String? ?? 'free',
      aiRecommendation: json['ai_recommendation'] as String? ?? '',
      nutritionStrategy:
          (json['nutrition_strategy'] as Map<String, dynamic>?) ?? {},
      days: (json['days'] as List<dynamic>?)
              ?.map((e) => AiDayPlan.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      shoppingList: (shop['categories'] as List<dynamic>?)
              ?.map((e) => AiShoppingCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      canRegenerateUnlimited: json['can_regenerate_unlimited'] as bool? ?? false,
      smartShopping: json['smart_shopping'] as bool? ?? false,
      regenerationCount: (json['regeneration_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'plan_id': planId,
        'duration_days': durationDays,
        'tier': tier,
        'ai_recommendation': aiRecommendation,
        'nutrition_strategy': nutritionStrategy,
        'days': days
            .map(
              (d) => {
                'date': d.date,
                'day_index': d.dayIndex,
                'meals': d.meals
                    .map(
                      (m) => {
                        'meal_type': m.mealType,
                        'title': m.title,
                        'guidance': m.guidance,
                        'ingredients': m.ingredients,
                        'nutrition': m.nutrition,
                        'recommended_recipes': m.recommendedRecipes
                            .map(
                              (r) => {
                                'id': r.id,
                                'title': r.title,
                                'image_url': r.imageUrl,
                                'calories': r.calories,
                                'cook_time_min': r.cookTimeMin,
                              },
                            )
                            .toList(),
                      },
                    )
                    .toList(),
                'day_totals': d.dayTotals,
              },
            )
            .toList(),
        'shopping_list': {
          'categories': shoppingList
              .map(
                (c) => {
                  'id': c.id,
                  'name': c.name,
                  'items': c.items
                      .map((i) => {'name': i.name, 'quantity': i.quantity})
                      .toList(),
                },
              )
              .toList(),
        },
        'can_regenerate_unlimited': canRegenerateUnlimited,
        'smart_shopping': smartShopping,
        'regeneration_count': regenerationCount,
      };
}

class MealPlanLimits {
  const MealPlanLimits({
    required this.tier,
    required this.allowedDurations,
    required this.maxDuration,
    required this.aiMealPlans,
    required this.smartShopping,
    required this.unlimitedRegeneration,
    required this.familyMealPlans,
    required this.premiumGuidance,
    this.maxFreeRegenerations = 0,
    this.canGenerateMealPlan = true,
    this.generationCooldownActive = false,
    this.generationCooldownDays = 7,
    this.mealPlanLastGeneratedAt,
    this.mealPlanCooldownEndsAt,
  });

  final String tier;
  final List<int> allowedDurations;
  final int maxDuration;
  final bool aiMealPlans;
  final bool smartShopping;
  final bool unlimitedRegeneration;
  final bool familyMealPlans;
  final bool premiumGuidance;
  final int maxFreeRegenerations;
  final bool canGenerateMealPlan;
  final bool generationCooldownActive;
  final int generationCooldownDays;
  final String? mealPlanLastGeneratedAt;
  final String? mealPlanCooldownEndsAt;

  factory MealPlanLimits.fromJson(Map<String, dynamic> json) {
    return MealPlanLimits(
      tier: json['tier'] as String? ?? 'free',
      allowedDurations: (json['allowed_durations'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [3],
      maxDuration: (json['max_duration'] as num?)?.toInt() ?? 3,
      aiMealPlans: json['ai_meal_plans'] as bool? ?? false,
      smartShopping: json['smart_shopping'] as bool? ?? false,
      unlimitedRegeneration: json['unlimited_regeneration'] as bool? ?? false,
      familyMealPlans: json['family_meal_plans'] as bool? ?? false,
      premiumGuidance: json['premium_guidance'] as bool? ?? false,
      maxFreeRegenerations:
          (json['max_free_regenerations'] as num?)?.toInt() ?? 0,
      canGenerateMealPlan: json['can_generate_meal_plan'] as bool? ?? true,
      generationCooldownActive:
          json['generation_cooldown_active'] as bool? ?? false,
      generationCooldownDays:
          (json['generation_cooldown_days'] as num?)?.toInt() ?? 7,
      mealPlanLastGeneratedAt: json['meal_plan_last_generated_at'] as String?,
      mealPlanCooldownEndsAt: json['meal_plan_cooldown_ends_at'] as String?,
    );
  }
}
