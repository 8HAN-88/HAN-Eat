import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../services/nutrition_prefs_service.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/survey_section_card.dart';
import 'meal_plan_survey_flow_screen.dart';

class MealPlanNutritionSettingsRoute {
  static const path = '/meal-plan/nutrition-settings';
  static const name = 'meal_plan_nutrition_settings';
}

/// Текущие настройки питания из анкеты + быстрое редактирование повторов.
class MealPlanNutritionSettingsScreen extends StatefulWidget {
  const MealPlanNutritionSettingsScreen({super.key});

  @override
  State<MealPlanNutritionSettingsScreen> createState() =>
      _MealPlanNutritionSettingsScreenState();
}

class _MealPlanNutritionSettingsScreenState
    extends State<MealPlanNutritionSettingsScreen> {
  bool _loading = true;
  bool _surveyComplete = false;
  NutritionSurveyData _data = const NutritionSurveyData();
  int _allergyCount = 0;
  bool _savingRepeats = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final complete = await NutritionPrefsService.isMealPlanSurveyComplete();
    final data = await NutritionPrefsService.loadSurveyData();
    final prefs = await NutritionPrefsService.loadForMealPlan();
    if (!mounted) return;
    setState(() {
      _surveyComplete = complete;
      _data = data;
      _allergyCount = (prefs['allergies'] as List?)?.length ?? 0;
      _loading = false;
    });
  }

  Future<void> _saveRepeats({
    required bool allow,
    required int intervalDays,
  }) async {
    setState(() => _savingRepeats = true);
    try {
      await NutritionPrefsService.saveSurvey(
        _data.copyWith(
          allowMealRepeats: allow,
          mealRepeatIntervalDays: intervalDays,
        ),
      );
      if (!mounted) return;
      setState(() {
        _data = _data.copyWith(
          allowMealRepeats: allow,
          mealRepeatIntervalDays: intervalDays,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки повторов сохранены')),
      );
    } finally {
      if (mounted) setState(() => _savingRepeats = false);
    }
  }

  Future<void> _openFullSurvey() async {
    final updated = await context.push<bool>(
      NutritionSurveyRoute.path,
      extra: true,
    );
    if (updated == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        title: const Text('Настройки питания'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_surveyComplete
              ? AppEmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Анкета не пройдена',
                  subtitle:
                      'Заполните короткий опрос — тогда здесь появятся ваши цели, '
                      'калории и предпочтения.',
                  action: FilledButton(
                    onPressed: _openFullSurvey,
                    child: const Text('Пройти анкету'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        'Текущие параметры для AI-плана. Чтобы изменить цель, '
                        'калории и диету — откройте полную анкету.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SettingsSection(
                        title: 'Цель',
                        children: [
                          _InfoTile(
                            label: 'Основная',
                            value: NutritionPrefsService.primaryGoalLabel(
                              _data.primaryGoal,
                            ),
                          ),
                          if (_data.goalTargets.isNotEmpty)
                            _InfoTile(
                              label: 'К чему стремитесь',
                              value: _data.goalTargets
                                  .map(NutritionPrefsService.goalTargetLabel)
                                  .join('\n'),
                            ),
                        ],
                      ),
                      _SettingsSection(
                        title: 'Рацион',
                        children: [
                          _InfoTile(
                            label: 'Калории',
                            value: _data.calories != null
                                ? '${_data.calories} ккал / день'
                                : 'Не указано',
                          ),
                          _InfoTile(
                            label: 'Приёмов в день',
                            value: '${_data.mealsPerDay}',
                          ),
                          _InfoTile(
                            label: 'Семья',
                            value: '${_data.familySize} чел.',
                          ),
                          _InfoTile(
                            label: 'Активность',
                            value: NutritionPrefsService.activityLevelLabel(
                              _data.activityLevel,
                            ),
                          ),
                          if (_data.diets.isNotEmpty)
                            _InfoTile(
                              label: 'Диеты',
                              value: _data.diets.join(', '),
                            ),
                          _InfoTile(
                            label: 'Бюджет',
                            value: NutritionPrefsService.budgetLevelLabel(
                              _data.budgetLevel,
                            ),
                          ),
                          if (_data.mealPreferences.isNotEmpty)
                            _InfoTile(
                              label: 'Предпочтения',
                              value: _data.mealPreferences.join(', '),
                            ),
                        ],
                      ),
                      _SettingsSection(
                        title: 'Готовка',
                        children: [
                          _InfoTile(
                            label: 'Время',
                            value: NutritionPrefsService.cookingTimeLabel(
                              _data.cookingTime,
                            ),
                          ),
                          _InfoTile(
                            label: 'Опыт',
                            value: NutritionPrefsService.cookingSkillLabel(
                              _data.cookingSkill,
                            ),
                          ),
                        ],
                      ),
                      _SettingsSection(
                        title: 'Аллергии',
                        children: [
                          _InfoTile(
                            label: 'Исключения',
                            value: _allergyCount > 0
                                ? 'Указано: $_allergyCount'
                                : 'Не указано',
                            trailing: TextButton(
                              onPressed: () async {
                                await context.push(AllergiesRoute.path);
                                await _load();
                              },
                              child: const Text('Изменить'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SurveySectionCard(
                        title: 'Повторы блюд',
                        subtitle: 'Применяется к новым AI-планам',
                        icon: Icons.repeat_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Разрешить повторы'),
                              subtitle: const Text(
                                'Одно и то же блюдо может появиться снова',
                              ),
                              value: _data.allowMealRepeats,
                              onChanged: _savingRepeats
                                  ? null
                                  : (v) => _saveRepeats(
                                        allow: v,
                                        intervalDays: _data.mealRepeatIntervalDays,
                                      ),
                            ),
                            if (_data.allowMealRepeats) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Интервал',
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final d in NutritionPrefsService
                                      .mealRepeatIntervalOptions)
                                    ChoiceChip(
                                      label: Text(
                                        NutritionPrefsService
                                            .mealRepeatIntervalLabel(d),
                                      ),
                                      selected:
                                          _data.mealRepeatIntervalDays == d,
                                      onSelected: _savingRepeats
                                          ? null
                                          : (_) => _saveRepeats(
                                                allow: true,
                                                intervalDays: d,
                                              ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _openFullSurvey,
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Изменить все настройки'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'После изменения анкеты создайте новый план, чтобы '
                        'применить параметры к меню.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
