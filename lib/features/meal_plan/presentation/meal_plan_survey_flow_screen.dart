import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../services/nutrition_prefs_service.dart';
import '../../../widgets/survey_section_card.dart';
import '../../../features/subscription/presentation/widgets/subscription_visuals.dart';

enum _SurveyStep {
  welcome,
  goal,
  goalTargets,
  body,
  activity,
  calories,
  weightPace,
  proteinFocus,
  familySize,
  energyHabits,
  healthFocus,
  diets,
  allergies,
  budget,
  cooking,
  mealsPerDay,
  preferences,
  repeats,
  summary,
}

class MealPlanSurveyFlowScreen extends StatefulWidget {
  const MealPlanSurveyFlowScreen({super.key, this.skipWelcome = false});

  /// Редактирование: сразу к шагам с уже сохранёнными ответами.
  final bool skipWelcome;

  @override
  State<MealPlanSurveyFlowScreen> createState() =>
      _MealPlanSurveyFlowScreenState();
}

class _MealPlanSurveyFlowScreenState extends State<MealPlanSurveyFlowScreen> {
  final _pageController = PageController();
  final _calorieController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  var _data = const NutritionSurveyData();
  var _steps = <_SurveyStep>[_SurveyStep.welcome, _SurveyStep.goal];
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  int _allergyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await NutritionPrefsService.loadSurveyData();
    final prefs = await NutritionPrefsService.loadForMealPlan();
    final allergies = (prefs['allergies'] as List?)?.length ?? 0;
    if (!mounted) return;
    setState(() {
      _data = data;
      _allergyCount = allergies;
      _calorieController.text = '${data.calories ?? 2000}';
      if (data.age != null) _ageController.text = '${data.age}';
      if (data.heightCm != null) _heightController.text = '${data.heightCm}';
      if (data.weightKg != null) _weightController.text = '${data.weightKg}';
      _steps = _buildSteps(data.primaryGoal);
      if (widget.skipWelcome && _steps.length > 1) {
        final start = _steps.indexOf(_SurveyStep.goal);
        _index = start >= 0 ? start : 1;
      }
      _loading = false;
    });
    if (widget.skipWelcome && _index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_index);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _calorieController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  List<_SurveyStep> _buildSteps(String? goal) {
    final steps = <_SurveyStep>[
      _SurveyStep.welcome,
      _SurveyStep.goal,
      _SurveyStep.goalTargets,
      _SurveyStep.body,
      _SurveyStep.activity,
      _SurveyStep.calories,
    ];
    switch (goal) {
      case 'weight_loss':
        steps.add(_SurveyStep.weightPace);
      case 'muscle_gain':
        steps.add(_SurveyStep.proteinFocus);
      case 'family':
        steps.add(_SurveyStep.familySize);
      case 'more_energy':
        steps.add(_SurveyStep.energyHabits);
      case 'health':
        steps.add(_SurveyStep.healthFocus);
    }
    if (goal != 'family') {
      steps.add(_SurveyStep.familySize);
    }
    steps.addAll([
      _SurveyStep.diets,
      _SurveyStep.allergies,
      _SurveyStep.budget,
      _SurveyStep.cooking,
      _SurveyStep.mealsPerDay,
      _SurveyStep.preferences,
      _SurveyStep.repeats,
      _SurveyStep.summary,
    ]);
    return steps;
  }

  void _rebuildStepsIfGoalChanged(String? goal) {
    final next = _buildSteps(goal);
    if (_listEqualsSteps(next, _steps)) return;
    final current = _steps[_index];
    setState(() {
      _steps = next;
      final newIdx = next.indexOf(current);
      _index = newIdx >= 0 ? newIdx : 0;
    });
    _pageController.jumpToPage(_index);
  }

  bool _listEqualsSteps(List<_SurveyStep> a, List<_SurveyStep> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _canProceed() {
    final step = _steps[_index];
    switch (step) {
      case _SurveyStep.goal:
        return _data.primaryGoal != null;
      case _SurveyStep.goalTargets:
        return _data.goalTargets.isNotEmpty;
      case _SurveyStep.calories:
        final cal = int.tryParse(_calorieController.text.trim());
        return cal != null && cal >= 800 && cal <= 6000;
      default:
        return true;
    }
  }

  void _syncBodyFromControllers() {
    final age = int.tryParse(_ageController.text.trim());
    final h = int.tryParse(_heightController.text.trim());
    final w = int.tryParse(_weightController.text.trim());
    _data = _data.copyWith(
      age: age,
      heightCm: h,
      weightKg: w,
    );
  }

  void _applySuggestedCalories() {
    _syncBodyFromControllers();
    final est = NutritionPrefsService.estimateDailyCalories(_data);
    if (est != null) {
      _calorieController.text = '$est';
      setState(() => _data = _data.copyWith(calories: est));
    }
  }

  Future<void> _next() async {
    if (!_canProceed()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите вариант или заполните поле')),
      );
      return;
    }
    if (_steps[_index] == _SurveyStep.body) _syncBodyFromControllers();
    if (_steps[_index] == _SurveyStep.calories) {
      final cal = int.tryParse(_calorieController.text.trim());
      setState(() => _data = _data.copyWith(calories: cal));
    }
    if (_steps[_index] == _SurveyStep.allergies) {
      final prefs = await NutritionPrefsService.loadForMealPlan();
      if (mounted) {
        setState(() {
          _allergyCount = (prefs['allergies'] as List?)?.length ?? 0;
        });
      }
    }
    if (_index >= _steps.length - 1) {
      await _save();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_index == 0) {
      context.pop(false);
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cal = int.tryParse(_calorieController.text.trim());
      await NutritionPrefsService.saveSurvey(
        _data.copyWith(calories: cal ?? _data.calories),
      );
      if (!mounted) return;
      context.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _stepShortTitle(_SurveyStep step) {
    return switch (step) {
      _SurveyStep.welcome => 'AI-план питания',
      _SurveyStep.goal => 'Ваша цель',
      _SurveyStep.goalTargets => 'К чему стремитесь',
      _SurveyStep.body => 'О вас',
      _SurveyStep.activity => 'Активность',
      _SurveyStep.calories => 'Калории',
      _SurveyStep.weightPace => 'Темп',
      _SurveyStep.proteinFocus => 'Белок',
      _SurveyStep.familySize => 'Семья',
      _SurveyStep.energyHabits => 'Энергия',
      _SurveyStep.healthFocus => 'Здоровье',
      _SurveyStep.diets => 'Стиль питания',
      _SurveyStep.allergies => 'Аллергии',
      _SurveyStep.budget => 'Бюджет',
      _SurveyStep.cooking => 'Готовка',
      _SurveyStep.mealsPerDay => 'Приёмы пищи',
      _SurveyStep.preferences => 'Предпочтения',
      _SurveyStep.repeats => 'Повторы блюд',
      _SurveyStep.summary => 'Итог',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final progress = (_index + 1) / _steps.length;
    final currentStep = _steps[_index];
    final isWelcome = currentStep == _SurveyStep.welcome;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isWelcome ? 'AI-план питания' : _stepShortTitle(currentStep),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!isWelcome)
              Text(
                'Шаг ${_index + 1} из ${_steps.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!isWelcome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(progress * 100).round()}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _StepPage(
                      centerContent: _steps[i] != _SurveyStep.diets &&
                          _steps[i] != _SurveyStep.goalTargets &&
                          _steps[i] != _SurveyStep.preferences,
                      child: _buildStepCard(_steps[i]),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
                  child: Row(
                    children: [
                      if (!isWelcome)
                        TextButton(
                          onPressed: _saving ? null : _back,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('Назад'),
                        ),
                      if (!isWelcome) const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _next,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  currentStep == _SurveyStep.summary
                                      ? 'Сохранить'
                                      : isWelcome
                                          ? 'Начать опрос'
                                          : 'Далее',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStepCard(_SurveyStep step) {
    switch (step) {
      case _SurveyStep.welcome:
        return _WelcomeCard();
      case _SurveyStep.goal:
        return SurveySectionCard(
          title: 'Зачем вам план питания?',
          subtitle: 'От ответа зависят следующие вопросы',
          icon: Icons.flag_rounded,
          child: _OptionTiles(
            options: const [
              _Opt('weight_loss', 'Похудение', Icons.trending_down_rounded),
              _Opt('maintain', 'Поддержание веса', Icons.balance_rounded),
              _Opt('muscle_gain', 'Набор мышц', Icons.fitness_center_rounded),
              _Opt('more_energy', 'Больше энергии', Icons.bolt_rounded),
              _Opt('family', 'Семейное меню', Icons.family_restroom_rounded),
              _Opt('health', 'Здоровье и самочувствие', Icons.favorite_rounded),
            ],
            selected: _data.primaryGoal,
            onSelected: (v) {
              final allowed = NutritionPrefsService.goalTargetsFor(v)
                  .map((e) => e.id)
                  .toSet();
              final kept =
                  _data.goalTargets.where(allowed.contains).toSet();
              setState(
                () => _data = _data.copyWith(primaryGoal: v, goalTargets: kept),
              );
              _rebuildStepsIfGoalChanged(v);
            },
          ),
        );
      case _SurveyStep.goalTargets:
        final options =
            NutritionPrefsService.goalTargetsFor(_data.primaryGoal);
        return SurveySectionCard(
          title: 'К чему хотите прийти?',
          subtitle: 'Можно выбрать несколько — учтём в AI-плане',
          icon: Icons.track_changes_rounded,
          child: _SurveyChipWrap(
            children: [
              for (final opt in options)
                FilterChip(
                  label: Text(opt.label),
                  showCheckmark: true,
                  selected: _data.goalTargets.contains(opt.id),
                  onSelected: (on) {
                    final next = Set<String>.from(_data.goalTargets);
                    if (on) {
                      next.add(opt.id);
                    } else {
                      next.remove(opt.id);
                    }
                    setState(() => _data = _data.copyWith(goalTargets: next));
                  },
                ),
            ],
          ),
        );
      case _SurveyStep.body:
        return SurveySectionCard(
          title: 'О вас',
          subtitle: 'Поможет точнее рассчитать калории (можно пропустить)',
          icon: Icons.person_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Пол', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in const [
                    ('female', 'Женский'),
                    ('male', 'Мужской'),
                    ('other', 'Другое'),
                  ])
                    ChoiceChip(
                      label: Text(e.$2),
                      selected: _data.sex == e.$1,
                      onSelected: (_) =>
                          setState(() => _data = _data.copyWith(sex: e.$1)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Возраст',
                        suffixText: 'лет',
                      ),
                      onChanged: (_) => _syncBodyFromControllers(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Рост',
                        suffixText: 'см',
                      ),
                      onChanged: (_) => _syncBodyFromControllers(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _weightController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Вес',
                  suffixText: 'кг',
                ),
                onChanged: (_) => _syncBodyFromControllers(),
              ),
            ],
          ),
        );
      case _SurveyStep.activity:
        return SurveySectionCard(
          title: 'Уровень активности',
          subtitle: 'Тренировки и движение в течение дня',
          icon: Icons.directions_run_rounded,
          child: _OptionTiles(
            options: const [
              _Opt('sedentary', 'Мало движения', Icons.weekend_rounded),
              _Opt('light', 'Лёгкая активность', Icons.directions_walk_rounded),
              _Opt('moderate', 'Умеренные тренировки', Icons.sports_gymnastics_rounded),
              _Opt('active', 'Активный образ', Icons.fitness_center_rounded),
              _Opt('very_active', 'Очень высокая нагрузка', Icons.whatshot_rounded),
            ],
            selected: _data.activityLevel,
            onSelected: (v) =>
                setState(() => _data = _data.copyWith(activityLevel: v)),
          ),
        );
      case _SurveyStep.calories:
        final suggested = NutritionPrefsService.estimateDailyCalories(_data);
        return SurveySectionCard(
          title: 'Калории в день',
          subtitle: suggested != null
              ? 'Рекомендуем около $suggested ккал для вашей цели'
              : 'Целевая норма для расчёта плана',
          icon: Icons.local_fire_department_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _calorieController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  suffixText: 'ккал',
                  border: OutlineInputBorder(),
                ),
              ),
              if (suggested != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _applySuggestedCalories,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: Text('Подставить $suggested ккал'),
                ),
              ],
            ],
          ),
        );
      case _SurveyStep.weightPace:
        return SurveySectionCard(
          title: 'Темп снижения веса',
          subtitle: 'Влияет на дефицит калорий',
          icon: Icons.speed_rounded,
          child: _OptionTiles(
            options: const [
              _Opt('slow', 'Плавно (~0,3 кг/нед)', Icons.trending_flat_rounded),
              _Opt('moderate', 'Умеренно (~0,5 кг/нед)', Icons.trending_down_rounded),
              _Opt('fast', 'Быстрее (~0,8 кг/нед)', Icons.flash_on_rounded),
            ],
            selected: _data.weightPace ?? 'moderate',
            onSelected: (v) =>
                setState(() => _data = _data.copyWith(weightPace: v)),
          ),
        );
      case _SurveyStep.proteinFocus:
        return SurveySectionCard(
          title: 'Акцент на белок',
          subtitle: 'Для набора мышечной массы',
          icon: Icons.egg_alt_rounded,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Повышенный белок в каждом приёме'),
            subtitle: const Text('Больше мяса, рыбы, бобовых, творога'),
            value: _data.highProteinFocus,
            onChanged: (v) =>
                setState(() => _data = _data.copyWith(highProteinFocus: v)),
          ),
        );
      case _SurveyStep.familySize:
        return SurveySectionCard(
          title: 'Сколько человек за столом?',
          subtitle: 'Порции и список покупок',
          icon: Icons.groups_rounded,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _data.familySize > 1
                      ? () => setState(
                            () => _data = _data.copyWith(
                              familySize: _data.familySize - 1,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Text(
                        '${_data.familySize}',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                      ),
                      Text(
                        _data.familySize == 1 ? 'человек' : 'человека',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _data.familySize < 8
                      ? () => setState(
                            () => _data = _data.copyWith(
                              familySize: _data.familySize + 1,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
        );
      case _SurveyStep.energyHabits:
        return SurveySectionCard(
          title: 'Когда проседает энергия?',
          icon: Icons.battery_3_bar_rounded,
          child: _OptionTiles(
            options: const [
              _Opt('morning', 'Утром сложно проснуться', Icons.wb_twilight_rounded),
              _Opt('afternoon', 'После обеда клонит в сон', Icons.wb_sunny_rounded),
              _Opt('evening', 'Вечером нет сил', Icons.nightlight_rounded),
              _Opt('steady', 'Нужен ровный уровень весь день', Icons.show_chart_rounded),
            ],
            selected: _data.energyHabit,
            onSelected: (v) =>
                setState(() => _data = _data.copyWith(energyHabit: v)),
          ),
        );
      case _SurveyStep.healthFocus:
        return SurveySectionCard(
          title: 'На что сделать акцент?',
          icon: Icons.health_and_safety_rounded,
          child: _OptionTiles(
            options: const [
              _Opt('digestion', 'Лёгкое пищеварение', Icons.eco_rounded),
              _Opt('heart', 'Сердце и сосуды', Icons.favorite_border_rounded),
              _Opt('sugar', 'Контроль сахара', Icons.water_drop_outlined),
              _Opt('immunity', 'Иммунитет', Icons.shield_outlined),
            ],
            selected: _data.healthFocus,
            onSelected: (v) =>
                setState(() => _data = _data.copyWith(healthFocus: v)),
          ),
        );
      case _SurveyStep.diets:
        return SurveySectionCard(
          title: 'Стиль питания',
          subtitle: 'Можно выбрать несколько',
          icon: Icons.restaurant_menu_rounded,
          child: _SurveyChipWrap(
            children: [
              for (final d in NutritionPrefsService.dietKeys)
                FilterChip(
                  label: Text(d),
                  showCheckmark: true,
                  selected: _data.diets.contains(d),
                  onSelected: (on) {
                    final next = Set<String>.from(_data.diets);
                    if (on) {
                      next.add(d);
                    } else {
                      next.remove(d);
                    }
                    setState(() => _data = _data.copyWith(diets: next));
                  },
                ),
            ],
          ),
        );
      case _SurveyStep.allergies:
        return SurveySectionCard(
          title: 'Аллергии и исключения',
          subtitle: _allergyCount > 0
              ? 'Указано: $_allergyCount'
              : 'Откроется экран аллергий',
          icon: Icons.no_food_rounded,
          child: FilledButton.tonalIcon(
            onPressed: () async {
              await context.push(AllergiesRoute.path);
              final prefs = await NutritionPrefsService.loadForMealPlan();
              if (mounted) {
                setState(() {
                  _allergyCount =
                      (prefs['allergies'] as List?)?.length ?? 0;
                });
              }
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Настроить аллергии'),
          ),
        );
      case _SurveyStep.budget:
        return SurveySectionCard(
          title: 'Бюджет на продукты',
          subtitle: 'Подберём рецепты и список покупок под ваш уровень',
          icon: Icons.payments_outlined,
          child: SurveyOptionList(
            selected: _data.budgetLevel,
            onSelected: (v) =>
                setState(() => _data = _data.copyWith(budgetLevel: v)),
            options: const [
              SurveyOption(
                id: 'low',
                label: 'Эконом',
                icon: Icons.savings_outlined,
                subtitle: 'Базовые продукты и сезонные овощи',
              ),
              SurveyOption(
                id: 'medium',
                label: 'Средний',
                icon: Icons.balance_rounded,
                subtitle: 'Сбалансированно, без лишних трат',
              ),
              SurveyOption(
                id: 'high',
                label: 'Выше среднего',
                icon: Icons.diamond_outlined,
                subtitle: 'Больше премиум-ингредиентов и разнообразия',
              ),
            ],
          ),
        );
      case _SurveyStep.cooking:
        return SurveySectionCard(
          title: 'Готовка',
          subtitle: 'Время и уверенность на кухне',
          icon: Icons.restaurant_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Сколько времени на блюдо?',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in const [
                    ('quick', 'До 20 мин'),
                    ('medium', '20–40 мин'),
                    ('relaxed', 'Не важно'),
                  ])
                    ChoiceChip(
                      label: Text(e.$2),
                      selected: _data.cookingTime == e.$1,
                      onSelected: (_) => setState(
                        () => _data = _data.copyWith(cookingTime: e.$1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Опыт',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in const [
                    ('beginner', 'Новичок'),
                    ('intermediate', 'Средний'),
                    ('advanced', 'Люблю готовить'),
                  ])
                    ChoiceChip(
                      label: Text(e.$2),
                      selected: _data.cookingSkill == e.$1,
                      onSelected: (_) => setState(
                        () => _data = _data.copyWith(cookingSkill: e.$1),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      case _SurveyStep.mealsPerDay:
        return SurveySectionCard(
          title: 'Приёмов пищи в день',
          icon: Icons.schedule_rounded,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _data.mealsPerDay > 2
                    ? () => setState(
                          () => _data = _data.copyWith(
                            mealsPerDay: _data.mealsPerDay - 1,
                          ),
                        )
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '${_data.mealsPerDay}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _data.mealsPerDay < 6
                    ? () => setState(
                          () => _data = _data.copyWith(
                            mealsPerDay: _data.mealsPerDay + 1,
                          ),
                        )
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        );
      case _SurveyStep.preferences:
        return SurveySectionCard(
          title: 'Предпочтения в меню',
          subtitle: 'Несколько вариантов',
          icon: Icons.tune_rounded,
          child: _SurveyChipWrap(
            children: [
              for (final p in NutritionPrefsService.mealPreferenceOptions)
                FilterChip(
                  label: Text(p),
                  showCheckmark: true,
                  selected: _data.mealPreferences.contains(p),
                  onSelected: (on) {
                    final next = Set<String>.from(_data.mealPreferences);
                    if (on) {
                      next.add(p);
                    } else {
                      next.remove(p);
                    }
                    setState(() => _data = _data.copyWith(mealPreferences: next));
                    if (_data.primaryGoal == 'muscle_gain' &&
                        p == 'Высокий белок' &&
                        on) {
                      setState(
                        () => _data = _data.copyWith(highProteinFocus: true),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      case _SurveyStep.repeats:
        return SurveySectionCard(
          title: 'Повторы блюд',
          subtitle: 'Как часто можно повторять одно и то же',
          icon: Icons.repeat_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Разрешить повторы'),
                value: _data.allowMealRepeats,
                onChanged: (v) => setState(
                  () => _data = _data.copyWith(allowMealRepeats: v),
                ),
              ),
              if (_data.allowMealRepeats) ...[
                const SizedBox(height: 8),
                Text('Интервал',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d
                        in NutritionPrefsService.mealRepeatIntervalOptions)
                      ChoiceChip(
                        label: Text(_repeatLabel(d)),
                        selected: _data.mealRepeatIntervalDays == d,
                        onSelected: (_) => setState(
                          () => _data = _data.copyWith(
                            mealRepeatIntervalDays: d,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      case _SurveyStep.summary:
        return SurveySectionCard(
          title: 'Готово к генерации',
          subtitle: 'Проверьте ключевые параметры',
          icon: Icons.check_circle_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow('Цель', _goalLabel(_data.primaryGoal)),
              if (_data.goalTargets.isNotEmpty)
                _SummaryRow(
                  'К чему стремитесь',
                  _data.goalTargets
                      .map(NutritionPrefsService.goalTargetLabel)
                      .join(', '),
                ),
              _SummaryRow('Калории', '${_data.calories ?? _calorieController.text} ккал'),
              _SummaryRow('Приёмов', '${_data.mealsPerDay}'),
              _SummaryRow('Семья', '${_data.familySize} чел.'),
              if (_data.diets.isNotEmpty)
                _SummaryRow('Диеты', _data.diets.join(', ')),
            ],
          ),
        );
    }
  }

  String _goalLabel(String? id) {
    return switch (id) {
      'weight_loss' => 'Похудение',
      'maintain' => 'Поддержание',
      'muscle_gain' => 'Набор мышц',
      'more_energy' => 'Энергия',
      'family' => 'Семейное меню',
      'health' => 'Здоровье',
      _ => '—',
    };
  }

  String _repeatLabel(int days) {
    if (days == 1) return '1 день';
    if (days >= 2 && days <= 4) return '$days дня';
    return '$days дней';
  }
}

class _SurveyChipWrap extends StatelessWidget {
  const _SurveyChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: subscriptionBrandGradientDecoration(
        radius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 56,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.95),
            ),
            const SizedBox(height: 20),
            Text(
              'Персональный AI-план',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Несколько коротких шагов — и меню подстроится под вашу цель, '
              'активность и вкусы.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.child,
    this.centerContent = true,
  });

  final Widget child;
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
            child: centerContent
                ? Align(
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(child.runtimeType.toString()),
                        child: child,
                      ),
                    ),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: KeyedSubtree(
                      key: ValueKey(child.runtimeType.toString()),
                      child: child,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _Opt {
  const _Opt(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _OptionTiles extends StatelessWidget {
  const _OptionTiles({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_Opt> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SurveyOptionList(
      selected: selected,
      onSelected: onSelected,
      options: [
        for (final o in options)
          SurveyOption(id: o.id, label: o.label, icon: o.icon),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class NutritionSurveyRoute {
  static const path = '/nutrition-survey';
  static const name = 'nutrition_survey';
}
