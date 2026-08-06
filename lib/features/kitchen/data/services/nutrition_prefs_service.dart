import 'package:shared_preferences/shared_preferences.dart';

/// Настройки питания из опроса AI-плана, Diet / Allergies.
class NutritionPrefsService {
  static const dietKeys = [
    'Вегетарианская',
    'Веганская',
    'Палео',
    'Кето',
    'Без глютена',
    'Низкоуглеводная',
    'Средиземноморская',
  ];

  static const allergyKeys = [
    'Молочные продукты',
    'Яйца',
    'Рыба',
    'Морепродукты',
    'Орехи',
    'Арахис',
    'Пшеница',
    'Соя',
    'Кунжут',
  ];

  static const mealPreferenceOptions = [
    'Быстрые блюда',
    'Разнообразное меню',
    'Бюджетные продукты',
    'Высокий белок',
    'Малоуглеводное',
  ];

  /// Варианты периодичности повтора блюд (дни).
  static const mealRepeatIntervalOptions = [2, 3, 4, 5, 7, 10, 14];

  static const primaryGoalKeys = [
    'weight_loss',
    'maintain',
    'muscle_gain',
    'more_energy',
    'family',
    'health',
  ];

  static const _keyAllowRepeats = 'meal_plan_allow_repeats';
  static const _keyRepeatInterval = 'meal_plan_repeat_interval_days';
  static const _keyMealPlanSurveyComplete = 'meal_plan_survey_completed';
  static const _keyPrimaryGoal = 'meal_plan_primary_goal';
  static const _keySex = 'meal_plan_sex';
  static const _keyAge = 'meal_plan_age';
  static const _keyHeightCm = 'meal_plan_height_cm';
  static const _keyWeightKg = 'meal_plan_weight_kg';
  static const _keyActivity = 'meal_plan_activity_level';
  static const _keyWeightPace = 'meal_plan_weight_pace';
  static const _keyHighProtein = 'meal_plan_high_protein_focus';
  static const _keyHealthFocus = 'meal_plan_health_focus';
  static const _keyEnergyHabit = 'meal_plan_energy_habit';
  static const _keyMealsPerDay = 'meal_plan_meals_per_day';
  static const _keyCookingTime = 'meal_plan_cooking_time';
  static const _keyCookingSkill = 'meal_plan_cooking_skill';
  static const _keyGoalTargets = 'meal_plan_goal_targets';

  /// Подцели «к чему хотите прийти» в зависимости от основной цели.
  static List<({String id, String label})> goalTargetsFor(String? primaryGoal) {
    switch (primaryGoal) {
      case 'weight_loss':
        return const [
          (id: 'lose_3_5kg', label: 'Сбросить 3–5 кг'),
          (id: 'lose_5_10kg', label: 'Сбросить 5–10 кг'),
          (id: 'lose_10plus', label: 'Сбросить более 10 кг'),
          (id: 'stable_appetite', label: 'Стабильный аппетит без срывов'),
          (id: 'less_snacking', label: 'Меньше перекусов'),
        ];
      case 'muscle_gain':
        return const [
          (id: 'gain_2_4kg', label: 'Набрать 2–4 кг'),
          (id: 'gain_5plus', label: 'Набрать 5+ кг'),
          (id: 'strength', label: 'Сила и выносливость'),
          (id: 'visible_abs', label: 'Рельеф / пресс'),
          (id: 'high_protein_meals', label: 'Больше белка в каждом приёме'),
        ];
      case 'more_energy':
        return const [
          (id: 'morning_energy', label: 'Энергия с утра'),
          (id: 'no_afternoon_slump', label: 'Без спада днём'),
          (id: 'better_sleep', label: 'Лучший сон'),
          (id: 'less_caffeine', label: 'Меньше зависимости от кофе'),
        ];
      case 'family':
        return const [
          (id: 'kids_variety', label: 'Разнообразие для детей'),
          (id: 'quick_dinners', label: 'Быстрые ужины'),
          (id: 'budget_family', label: 'Уложиться в бюджет'),
          (id: 'one_pot_meals', label: 'Блюда «в одной кастрюле»'),
        ];
      case 'health':
        return const [
          (id: 'less_sugar', label: 'Меньше сахара'),
          (id: 'more_veggies', label: 'Больше овощей'),
          (id: 'gut_health', label: 'Комфорт ЖКТ'),
          (id: 'hydration', label: 'Режим воды'),
        ];
      case 'maintain':
        return const [
          (id: 'maintain_habits', label: 'Закрепить привычки'),
          (id: 'flexible_weekends', label: 'Гибкость на выходных'),
          (id: 'meal_prep', label: 'Заготовки на неделю'),
        ];
      default:
        return const [
          (id: 'maintain_habits', label: 'Сбалансированное питание'),
          (id: 'more_veggies', label: 'Больше овощей'),
        ];
    }
  }

  static String goalTargetLabel(String id) {
    for (final g in primaryGoalKeys) {
      for (final t in goalTargetsFor(g)) {
        if (t.id == id) return t.label;
      }
    }
    return id;
  }

  static String primaryGoalLabel(String? id) => switch (id) {
        'weight_loss' => 'Похудение',
        'maintain' => 'Поддержание веса',
        'muscle_gain' => 'Набор мышц',
        'more_energy' => 'Больше энергии',
        'family' => 'Семейное меню',
        'health' => 'Здоровье и самочувствие',
        _ => 'Не указано',
      };

  static String activityLevelLabel(String? id) => switch (id) {
        'sedentary' => 'Сидячий образ жизни',
        'light' => 'Лёгкая активность',
        'moderate' => 'Умеренные тренировки',
        'active' => 'Активный образ',
        'very_active' => 'Очень высокая нагрузка',
        _ => 'Не указано',
      };

  static String budgetLevelLabel(String level) => switch (level) {
        'low' => 'Эконом',
        'high' => 'Выше среднего',
        _ => 'Средний',
      };

  static String cookingTimeLabel(String? id) => switch (id) {
        'quick' => 'До 20 мин',
        'medium' => '20–40 мин',
        'relaxed' => 'Не важно',
        _ => 'Не указано',
      };

  static String cookingSkillLabel(String? id) => switch (id) {
        'beginner' => 'Новичок',
        'intermediate' => 'Средний',
        'advanced' => 'Люблю готовить',
        _ => 'Не указано',
      };

  static String mealRepeatIntervalLabel(int days) {
    if (days == 1) return '1 день';
    if (days >= 2 && days <= 4) return '$days дня';
    return '$days дней';
  }

  static Future<Map<String, dynamic>> loadForMealPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final diets = <String>[];
    for (final key in dietKeys) {
      if (prefs.getBool('diet_$key') == true) diets.add(key);
    }

    final allergies = <String>[];
    for (final key in allergyKeys) {
      if (prefs.getBool('allergy_$key') == true) allergies.add(key);
    }
    allergies.addAll(prefs.getStringList('custom_allergies') ?? []);

    return {
      'daily_calories': prefs.getInt('calorie_limit'),
      'diets': diets,
      'allergies': allergies,
      'budget_level': prefs.getString('meal_plan_budget') ?? 'medium',
      'meal_preferences': prefs.getStringList('meal_preferences') ?? <String>[],
      'family_size': prefs.getInt('meal_plan_family_size') ?? 1,
      'allow_meal_repeats': prefs.getBool(_keyAllowRepeats) ?? true,
      'meal_repeat_interval_days': _clampInterval(
        prefs.getInt(_keyRepeatInterval) ?? 4,
      ),
      'primary_goal': prefs.getString(_keyPrimaryGoal),
      'activity_level': prefs.getString(_keyActivity),
      'sex': prefs.getString(_keySex),
      'age': prefs.getInt(_keyAge),
      'height_cm': prefs.getInt(_keyHeightCm),
      'weight_kg': prefs.getInt(_keyWeightKg),
      'meals_per_day': prefs.getInt(_keyMealsPerDay),
      'cooking_time': prefs.getString(_keyCookingTime),
      'cooking_skill': prefs.getString(_keyCookingSkill),
      'weight_pace': prefs.getString(_keyWeightPace),
      'health_focus': prefs.getString(_keyHealthFocus),
      'energy_habit': prefs.getString(_keyEnergyHabit),
      'high_protein_focus': prefs.getBool(_keyHighProtein) ?? false,
      'goal_targets': prefs.getStringList(_keyGoalTargets) ?? <String>[],
    };
  }

  static int _clampInterval(int days) {
    if (days < 1) return 1;
    if (days > 21) return 21;
    return days;
  }

  static Future<NutritionSurveyData> loadSurveyData() async {
    final prefs = await SharedPreferences.getInstance();
    final diets = <String>{};
    for (final key in dietKeys) {
      if (prefs.getBool('diet_$key') == true) diets.add(key);
    }
    return NutritionSurveyData(
      primaryGoal: prefs.getString(_keyPrimaryGoal),
      sex: prefs.getString(_keySex),
      age: prefs.getInt(_keyAge),
      heightCm: prefs.getInt(_keyHeightCm),
      weightKg: prefs.getInt(_keyWeightKg),
      activityLevel: prefs.getString(_keyActivity),
      weightPace: prefs.getString(_keyWeightPace),
      highProteinFocus: prefs.getBool(_keyHighProtein) ?? false,
      healthFocus: prefs.getString(_keyHealthFocus),
      energyHabit: prefs.getString(_keyEnergyHabit),
      familySize: prefs.getInt('meal_plan_family_size') ?? 1,
      mealsPerDay: prefs.getInt(_keyMealsPerDay) ?? 3,
      cookingTime: prefs.getString(_keyCookingTime),
      cookingSkill: prefs.getString(_keyCookingSkill),
      calories: prefs.getInt('calorie_limit'),
      diets: diets,
      budgetLevel: prefs.getString('meal_plan_budget') ?? 'medium',
      mealPreferences: Set<String>.from(
        prefs.getStringList('meal_preferences') ?? [],
      ),
      allowMealRepeats: prefs.getBool(_keyAllowRepeats) ?? true,
      mealRepeatIntervalDays: _clampInterval(
        prefs.getInt(_keyRepeatInterval) ?? 4,
      ),
      goalTargets: Set<String>.from(
        prefs.getStringList(_keyGoalTargets) ?? [],
      ),
    );
  }

  static Future<void> saveSurvey(NutritionSurveyData data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data.calories != null && data.calories! > 0) {
      await prefs.setInt('calorie_limit', data.calories!);
    }
    if (data.primaryGoal != null) {
      await prefs.setString(_keyPrimaryGoal, data.primaryGoal!);
    }
    if (data.sex != null) {
      await prefs.setString(_keySex, data.sex!);
    }
    if (data.age != null) await prefs.setInt(_keyAge, data.age!);
    if (data.heightCm != null) {
      await prefs.setInt(_keyHeightCm, data.heightCm!);
    }
    if (data.weightKg != null) {
      await prefs.setInt(_keyWeightKg, data.weightKg!);
    }
    if (data.activityLevel != null) {
      await prefs.setString(_keyActivity, data.activityLevel!);
    }
    if (data.weightPace != null) {
      await prefs.setString(_keyWeightPace, data.weightPace!);
    }
    if (data.healthFocus != null) {
      await prefs.setString(_keyHealthFocus, data.healthFocus!);
    }
    if (data.energyHabit != null) {
      await prefs.setString(_keyEnergyHabit, data.energyHabit!);
    }
    if (data.cookingTime != null) {
      await prefs.setString(_keyCookingTime, data.cookingTime!);
    }
    if (data.cookingSkill != null) {
      await prefs.setString(_keyCookingSkill, data.cookingSkill!);
    }
    await prefs.setBool(_keyHighProtein, data.highProteinFocus);
    await prefs.setInt('meal_plan_family_size', data.familySize.clamp(1, 8));
    await prefs.setInt(_keyMealsPerDay, data.mealsPerDay.clamp(2, 6));

    for (final key in dietKeys) {
      await prefs.setBool('diet_$key', data.diets.contains(key));
    }
    await prefs.setString('meal_plan_budget', data.budgetLevel);
    await prefs.setStringList(
      'meal_preferences',
      data.mealPreferences.toList(),
    );
    await prefs.setBool(_keyAllowRepeats, data.allowMealRepeats);
    await prefs.setInt(
      _keyRepeatInterval,
      _clampInterval(data.mealRepeatIntervalDays),
    );
    await prefs.setStringList(_keyGoalTargets, data.goalTargets.toList());
    await prefs.setBool('nutrition_onboarding_done', true);
    await prefs.setBool(_keyMealPlanSurveyComplete, true);
  }

  /// Полный опрос AI-плана пройден.
  static Future<bool> isMealPlanSurveyComplete() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyMealPlanSurveyComplete) != true) return false;
    final goal = prefs.getString(_keyPrimaryGoal);
    final cal = prefs.getInt('calorie_limit');
    return goal != null &&
        goal.isNotEmpty &&
        cal != null &&
        cal >= 800;
  }

  static Future<void> saveFamilySize(int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('meal_plan_family_size', size.clamp(1, 8));
  }

  static Future<void> saveCalorieLimit(int calories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('calorie_limit', calories);
  }

  /// Лёгкие подсказки из онбординга — без отметки «опрос пройден».
  static Future<void> saveOnboardingNutrition({
    required int? calories,
    List<String> diets = const [],
    bool allowMealRepeats = true,
    int mealRepeatIntervalDays = 4,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (calories != null && calories > 0) {
      await prefs.setInt('calorie_limit', calories);
    }
    for (final key in dietKeys) {
      await prefs.setBool('diet_$key', diets.contains(key));
    }
    await prefs.setBool(_keyAllowRepeats, allowMealRepeats);
    await prefs.setInt(
      _keyRepeatInterval,
      _clampInterval(mealRepeatIntervalDays),
    );
    await prefs.setBool('nutrition_onboarding_done', true);
  }

  static Future<void> resetOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', false);
  }

  /// Подсказка калорий по антропометрии (упрощённо).
  static int? estimateDailyCalories(NutritionSurveyData data) {
    final w = data.weightKg;
    final h = data.heightCm;
    final a = data.age;
    if (w == null || h == null || a == null || a < 10) return null;
    final isFemale = data.sex == 'female';
    var bmr = 10 * w + 6.25 * h - 5 * a + (isFemale ? -161 : 5);
    const activityMult = {
      'sedentary': 1.2,
      'light': 1.375,
      'moderate': 1.55,
      'active': 1.725,
      'very_active': 1.9,
    };
    final mult = activityMult[data.activityLevel] ?? 1.375;
    var target = (bmr * mult).round();
    switch (data.primaryGoal) {
      case 'weight_loss':
        final cut = switch (data.weightPace) {
          'slow' => 0.92,
          'fast' => 0.78,
          _ => 0.85,
        };
        target = (target * cut).round();
      case 'muscle_gain':
        target = (target * 1.1).round();
      case 'more_energy':
        target = (target * 1.05).round();
      default:
        break;
    }
    return target.clamp(1200, 4500);
  }
}

class NutritionSurveyData {
  const NutritionSurveyData({
    this.primaryGoal,
    this.sex,
    this.age,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.weightPace,
    this.highProteinFocus = false,
    this.healthFocus,
    this.energyHabit,
    this.familySize = 1,
    this.mealsPerDay = 3,
    this.cookingTime,
    this.cookingSkill,
    this.calories,
    this.diets = const {},
    this.budgetLevel = 'medium',
    this.mealPreferences = const {},
    this.allowMealRepeats = true,
    this.mealRepeatIntervalDays = 4,
    this.goalTargets = const {},
  });

  final String? primaryGoal;
  final String? sex;
  final int? age;
  final int? heightCm;
  final int? weightKg;
  final String? activityLevel;
  final String? weightPace;
  final bool highProteinFocus;
  final String? healthFocus;
  final String? energyHabit;
  final int familySize;
  final int mealsPerDay;
  final String? cookingTime;
  final String? cookingSkill;
  final int? calories;
  final Set<String> diets;
  final String budgetLevel;
  final Set<String> mealPreferences;
  final bool allowMealRepeats;
  final int mealRepeatIntervalDays;
  final Set<String> goalTargets;

  NutritionSurveyData copyWith({
    String? primaryGoal,
    String? sex,
    int? age,
    int? heightCm,
    int? weightKg,
    String? activityLevel,
    String? weightPace,
    bool? highProteinFocus,
    String? healthFocus,
    String? energyHabit,
    int? familySize,
    int? mealsPerDay,
    String? cookingTime,
    String? cookingSkill,
    int? calories,
    Set<String>? diets,
    String? budgetLevel,
    Set<String>? mealPreferences,
    bool? allowMealRepeats,
    int? mealRepeatIntervalDays,
    Set<String>? goalTargets,
  }) {
    return NutritionSurveyData(
      primaryGoal: primaryGoal ?? this.primaryGoal,
      sex: sex ?? this.sex,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      weightPace: weightPace ?? this.weightPace,
      highProteinFocus: highProteinFocus ?? this.highProteinFocus,
      healthFocus: healthFocus ?? this.healthFocus,
      energyHabit: energyHabit ?? this.energyHabit,
      familySize: familySize ?? this.familySize,
      mealsPerDay: mealsPerDay ?? this.mealsPerDay,
      cookingTime: cookingTime ?? this.cookingTime,
      cookingSkill: cookingSkill ?? this.cookingSkill,
      calories: calories ?? this.calories,
      diets: diets ?? this.diets,
      budgetLevel: budgetLevel ?? this.budgetLevel,
      mealPreferences: mealPreferences ?? this.mealPreferences,
      allowMealRepeats: allowMealRepeats ?? this.allowMealRepeats,
      mealRepeatIntervalDays:
          mealRepeatIntervalDays ?? this.mealRepeatIntervalDays,
      goalTargets: goalTargets ?? this.goalTargets,
    );
  }
}
