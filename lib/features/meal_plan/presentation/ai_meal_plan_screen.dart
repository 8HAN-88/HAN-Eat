import 'dart:async';
import '../../../utils/api_error_parser.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_router.dart';
import '../../../models/ai_meal_plan.dart';
import '../../../services/ai_meal_plan_service.dart';
import '../../../services/api_service.dart';
import '../../../services/product_analytics.dart';
import '../../../services/nutrition_prefs_service.dart';
import '../../../services/meal_plan_gate.dart';
import '../../../services/shopping_service.dart';
import 'meal_plan_analytics_screen.dart';
import 'meal_plan_nutrition_settings_screen.dart';
import 'meal_plan_survey_flow_screen.dart';
import 'widgets/ai_meal_plan_widgets.dart';
import '../../../core/theme/color_schemes.dart';

/// AI-план питания: рекомендации, блюда, опциональные рецепты, регенерация, shopping.
class AiMealPlanScreen extends StatefulWidget {
  const AiMealPlanScreen({super.key});

  @override
  State<AiMealPlanScreen> createState() => _AiMealPlanScreenState();
}

class _AiMealPlanScreenState extends State<AiMealPlanScreen> {
  final _service = AiMealPlanService.instance;
  bool _loading = true;
  String? _error;
  MealPlanLimits? _limits;
  AiMealPlan? _plan;
  bool _surveyComplete = false;
  int _selectedDayIndex = 0;
  int? _regeneratingMealIndex;

  bool get _canRegenerateMore {
    final plan = _plan;
    if (plan == null) return false;
    return plan.canRegenerateUnlimited;
  }

  bool _handleMealPlanError(Object e) {
    if (!mounted) return true;
    if (e is HanMealPlanCooldownException) {
      unawaited(MealPlanGate.showCooldownPaywall(context));
      return true;
    }
    if (e is HanPlusRequiredException) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      context.push(SubscriptionRoute.path);
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userVisibleError(e, fallback: 'Не удалось выполнить действие')),
      ),
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Отступ снизу под компактную панель (без двойного учёта tab bar).
  double _contentBottomPadding(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    return 16 + 56 + safe;
  }

  Future<bool> _ensureMealPlanSurvey() async {
    if (await NutritionPrefsService.isMealPlanSurveyComplete()) {
      if (mounted) setState(() => _surveyComplete = true);
      return true;
    }
    if (!mounted) return false;
    final done = await context.push<bool>(NutritionSurveyRoute.path);
    if (done == true && mounted) {
      setState(() => _surveyComplete = true);
    }
    return done == true;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final limits = await _service.fetchLimits();
      final surveyDone =
          await NutritionPrefsService.isMealPlanSurveyComplete();

      if (_service.activePlan != null) {
        setState(() {
          _limits = limits;
          _plan = _service.activePlan;
          _surveyComplete = surveyDone;
          _loading = false;
        });
        return;
      }

      final saved = await _service.loadLatestSaved();
      if (saved != null && mounted) {
        final useSaved = await _askUseSavedPlan(saved);
        if (useSaved == true) {
          setState(() {
            _limits = limits;
            _plan = saved;
            _surveyComplete = surveyDone;
            _loading = false;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _limits = limits;
        _plan = null;
        _surveyComplete = surveyDone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is HanPlusRequiredException) {
        context.push(SubscriptionRoute.path);
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить план питания');
        _loading = false;
      });
    }
  }

  Future<bool?> _askUseSavedPlan(AiMealPlan saved) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранённый план'),
        content: Text(
          'Найден план на ${saved.durationDays} дн.\n'
          '${saved.aiRecommendation.isNotEmpty ? saved.aiRecommendation : 'Продолжить?'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Новый план'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
  }

  Future<_PlanPick?> _pickDuration(MealPlanLimits limits) async {
    var familySize = 1;
    return showModalBottomSheet<_PlanPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  24 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Срок плана питания',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      limits.smartShopping
                          ? 'Персональный план с умным списком покупок'
                          : limits.generationCooldownActive
                              ? 'Новый план — позже или с H.A.N. AI'
                              : 'Бесплатно: 3 дня с базовыми рекомендациями',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (limits.familyMealPlans) ...[
                      const SizedBox(height: 16),
                      Text('Семейный план (Pro)', style: Theme.of(ctx).textTheme.titleSmall),
                      Row(
                        children: [
                          IconButton(
                            onPressed: familySize > 1
                                ? () => setModalState(() => familySize--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$familySize чел.', style: Theme.of(ctx).textTheme.titleMedium),
                          IconButton(
                            onPressed: familySize < 8
                                ? () => setModalState(() => familySize++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    ...limits.allowedDurations.map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await NutritionPrefsService.saveFamilySize(familySize);
                              if (ctx.mounted) {
                                Navigator.pop(ctx, _PlanPick(d, familySize));
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_today_rounded,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      '$d ${_dayLabel(d)}',
                                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyToCalendar() async {
    final plan = _plan;
    if (plan == null) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить в календарь'),
        content: const Text(
          'Заменить существующие блюда на эти даты или добавить поверх?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Добавить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Заменить'),
          ),
        ],
      ),
    );
    if (replace == null) return;
    try {
      final n = await _service.applyActivePlanToCalendar(replaceExisting: replace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено блюд в календарь: $n')),
      );
      context.push(MealPlanRoute.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  String _formatDayTitle(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    return DateFormat('EEEE, d MMMM', 'ru').format(parsed);
  }

  String _dayLabel(int d) {
    if (d == 1) return 'день';
    if (d < 5) return 'дня';
    return 'дней';
  }

  String _dayWord(int d) {
    if (d == 1) return 'день';
    if (d >= 2 && d <= 4) return 'дня';
    return 'дней';
  }

  Future<void> _regenerate({
    required String scope,
    String? modifier,
    int? mealIndex,
  }) async {
    setState(() => _regeneratingMealIndex = mealIndex);
    try {
      final prevTitle = _plan?.days[_selectedDayIndex].meals[mealIndex ?? 0].title;
      final plan = await _service.regenerate(
        scope: scope,
        dayIndex: _selectedDayIndex,
        mealIndex: mealIndex ?? 0,
        modifier: modifier,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
      if (scope == 'meal' && mealIndex != null) {
        final newTitle = plan.days[_selectedDayIndex].meals[mealIndex].title;
        if (newTitle != prevTitle) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Новое блюдо: $newTitle')),
          );
        }
      } else if (scope == 'plan' || scope == 'day') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('План обновлён')),
        );
      }
    } catch (e) {
      _handleMealPlanError(e);
    } finally {
      if (mounted) setState(() => _regeneratingMealIndex = null);
    }
  }

  Future<void> _openNutritionSettings() async {
    await context.push(MealPlanNutritionSettingsRoute.path);
    if (!mounted) return;
    setState(() {
      _surveyComplete = true;
    });
  }

  Future<void> _openNutritionSurvey() async {
    final updated = await context.push<bool>(NutritionSurveyRoute.path);
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Настройки обновлены. Создайте новый план, чтобы применить их.',
          ),
        ),
      );
    }
  }

  Future<void> _createNewPlan() async {
    if (!await _ensureMealPlanSurvey()) return;
    final limits = _limits ?? await _service.fetchLimits();
    if (!await MealPlanGate.ensureCanGenerate(context, limits)) return;
    final picked = await _pickDuration(limits);
    if (picked == null || !mounted) return;
    setState(() => _loading = true);
    try {
      _service.clear();
      final plan = await _service.generate(durationDays: picked.duration);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selectedDayIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _handleMealPlanError(e);
    }
  }

  Future<void> _showSavedPlans() async {
    try {
      final rows = await _service.listSaved(limit: 15);
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранённых планов пока нет')),
        );
        return;
      }
      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  'Сохранённые планы',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              ...rows.map((row) {
                final days = (row['duration_days'] as num?)?.toInt() ??
                    (row['plan'] as Map?)?['duration_days'] as int? ??
                    0;
                final rec = row['ai_recommendation'] as String? ??
                    (row['plan'] as Map?)?['ai_recommendation'] as String? ??
                    '';
                final created = row['created_at'] as String? ?? '';
                return ListTile(
                  title: Text('$days дн.'),
                  subtitle: Text(
                    rec.isNotEmpty ? rec : created,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, row),
                );
              }),
            ],
          ),
        ),
      );
      if (picked != null && mounted) {
        await _openSavedPlanRow(picked);
      }
    } catch (e) {
      _handleMealPlanError(e);
    }
  }

  Future<void> _openSavedPlanRow(Map<String, dynamic> row) async {
    var planJson = row['plan'] as Map<String, dynamic>?;
    final hasDays = planJson != null &&
        planJson['days'] is List &&
        (planJson['days'] as List).isNotEmpty;
    if (!hasDays) {
      final planId = row['plan_id'] as String?;
      if (planId == null || planId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить план')),
        );
        return;
      }
      setState(() => _loading = true);
      try {
        planJson = await ApiService.getSavedMealPlanById(planId);
        if (planJson == null) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('План не найден на сервере')),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          _handleMealPlanError(e);
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _plan = AiMealPlan.fromJson(planJson!);
      _service.setActivePlan(_plan!);
      _selectedDayIndex = 0;
      _loading = false;
    });
  }

  void _previewShoppingList() {
    final plan = _plan;
    if (plan == null || plan.shoppingList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Список покупок пуст')),
      );
      return;
    }
    final smartShopping = plan.smartShopping || (_limits?.smartShopping ?? false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          smartShopping ? 'Список покупок' : 'Ингредиенты по плану',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      if (smartShopping)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _applyShoppingList();
                          },
                          child: const Text('В мой список'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final cat in plan.shoppingList) ...[
                        Text(
                          cat.name,
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 6),
                        ...cat.items.map(
                          (i) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(i.name),
                            subtitle: i.quantity != null &&
                                    i.quantity!.isNotEmpty
                                ? Text(i.quantity!)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!smartShopping) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Умный список покупок с категориями — в H.A.N. AI',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _applyShoppingList() async {
    final plan = _plan;
    if (plan == null) return;
    for (final cat in plan.shoppingList) {
      final catalog = cat.items
          .map((i) => (name: i.name, quantity: i.quantity))
          .toList();
      await ShoppingService.instance.addCatalogItems(
        catalog,
        group: cat.name,
      );
    }
    await ApiService.logMealPlanShoppingApplied();
    await ProductAnalytics.logEvent(eventType: 'meal_plan_shopping_applied');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Список покупок обновлён')),
    );
  }

  Future<void> _showPlanActionsMenu() async {
    final plan = _plan;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Действия с планом',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AiMealPlanMenuTile(
                    icon: Icons.quiz_rounded,
                    title: 'Пройти опрос заново',
                    subtitle: 'Цель, калории, диета и предпочтения',
                    onTap: () {
                      Navigator.pop(ctx);
                      _openNutritionSurvey();
                    },
                  ),
                  AiMealPlanMenuTile(
                    icon: Icons.history_rounded,
                    title: 'Сохранённые планы',
                    subtitle: 'Открыть ранее созданные',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showSavedPlans();
                    },
                  ),
                  AiMealPlanMenuTile(
                    icon: Icons.add_circle_outline_rounded,
                    title: 'Новый план',
                    subtitle: _limits != null && !_limits!.canGenerateMealPlan
                        ? 'Доступен позже или с H.A.N. AI'
                        : 'Сгенерировать с нуля',
                    accentColor: AppColors.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _createNewPlan();
                    },
                  ),
                  if (plan != null && plan.canRegenerateUnlimited)
                    AiMealPlanMenuTile(
                      icon: Icons.autorenew_rounded,
                      title: 'Обновить весь план',
                      subtitle: 'Новые блюда на все дни',
                      onTap: () {
                        Navigator.pop(ctx);
                        _regenerate(scope: 'plan', modifier: 'refresh');
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        title: const Text('План питания'),
        actions: [
          IconButton(
            tooltip: 'Меню',
            onPressed: _showPlanActionsMenu,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          if (_plan != null) ...[
            IconButton(
              tooltip: 'Просмотр списка покупок',
              onPressed: _previewShoppingList,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
            IconButton(
              tooltip: 'Аналитика',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MealPlanAnalyticsScreen(),
                ),
              ),
              icon: const Icon(Icons.insights_outlined),
            ),
          ],
        ],
      ),
      body: _loading
          ? const AiMealPlanLoadingView()
          : _error != null
              ? AiMealPlanErrorView(
                  message: _error!,
                  onRetry: _bootstrap,
                )
              : _plan == null
                  ? AiMealPlanStartView(
                      surveyComplete: _surveyComplete,
                      onCreatePlan: _createNewPlan,
                      onOpenSaved: _showSavedPlans,
                    )
                  : _buildBody(context),
      bottomNavigationBar: _plan == null
          ? null
          : AiMealPlanBottomBar(
              onCalendar: _applyToCalendar,
              onShopping: _previewShoppingList,
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottom = _contentBottomPadding(context);
    final plan = _plan!;
    final theme = Theme.of(context);
    if (plan.days.isEmpty) {
      return AiMealPlanErrorView(
        message: 'План пуст. Создайте новый план в меню.',
        onRetry: _createNewPlan,
      );
    }
    final dayIndex = _selectedDayIndex.clamp(0, plan.days.length - 1);
    final day = plan.days[dayIndex];
    final timing = plan.nutritionStrategy['meal_timing_notes'] as String?;
    final userPrefs =
        plan.nutritionStrategy['user_preferences'] as Map<String, dynamic>?;
    final allowRepeats = userPrefs?['allow_meal_repeats'] as bool? ?? true;
    final repeatDays =
        (userPrefs?['meal_repeat_interval_days'] as num?)?.toInt() ?? 4;

    final metaChips = <AiMetaChipData>[
      if (allowRepeats)
        AiMetaChipData(
          icon: Icons.repeat_rounded,
          label: 'Повторы: раз в $repeatDays ${_dayWord(repeatDays)}',
        )
      else
        const AiMetaChipData(
          icon: Icons.shuffle_rounded,
          label: 'Без повторов блюд',
        ),
      if (timing != null && timing.isNotEmpty)
        AiMetaChipData(icon: Icons.schedule_rounded, label: timing),
    ];

    final regenActions = plan.canRegenerateUnlimited
        ? <AiRegenActionData>[
            AiRegenActionData(
              label: 'Заменить блюдо',
              icon: Icons.swap_horiz_rounded,
              onTap: () => _regenerate(scope: 'meal', modifier: 'replace'),
            ),
            AiRegenActionData(
              label: 'Обновить день',
              icon: Icons.today_rounded,
              onTap: () => _regenerate(scope: 'day', modifier: 'refresh'),
            ),
            AiRegenActionData(
              label: 'Весь план',
              icon: Icons.autorenew_rounded,
              onTap: () => _regenerate(scope: 'plan', modifier: 'refresh'),
            ),
            AiRegenActionData(
              label: 'Быстрее',
              icon: Icons.bolt_rounded,
              onTap: () => _regenerate(scope: 'meal', modifier: 'faster'),
            ),
            AiRegenActionData(
              label: 'Дешевле',
              icon: Icons.savings_outlined,
              onTap: () => _regenerate(scope: 'meal', modifier: 'cheaper'),
            ),
          ]
        : <AiRegenActionData>[];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              AiMealPlanHero(
                durationDays: plan.durationDays,
                aiRecommendation: plan.aiRecommendation,
                dayCalories: day.dayTotals['calories']?.round(),
              ),
              const SizedBox(height: 14),
              AiMealPlanMetaRow(chips: metaChips),
              if (!plan.canRegenerateUnlimited) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Обновление блюд, дней и умный список покупок — в H.A.N. AI',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _openNutritionSettings,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Настройки питания и повторы',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Посмотреть и изменить',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AiMealPlanDaySelector(
                count: plan.days.length,
                selectedIndex: dayIndex,
                onSelected: (i) => setState(() => _selectedDayIndex = i),
              ),
              if (regenActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                AiMealPlanRegenBar(actions: regenActions),
              ],
              const SizedBox(height: 18),
              Text(
                _formatDayTitle(day.date),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              AiMealPlanMacroRow(
                calories: day.dayTotals['calories']?.round(),
                protein: day.dayTotals['protein_g'],
                fat: day.dayTotals['fat_g'],
                carbs: day.dayTotals['carbs_g'],
              ),
              const SizedBox(height: 18),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final meal = day.meals[i];
                return AiMealPlanMealCard(
                  key: ValueKey(
                    '${day.dayIndex}-$i-${meal.title}-'
                    '${meal.recommendedRecipes.map((r) => r.id ?? r.title).join("|")}',
                  ),
                  meal: meal,
                  loading: _regeneratingMealIndex == i,
                  canRegenerate: _canRegenerateMore,
                  onReplace: () => _regenerate(
                    scope: 'meal',
                    modifier: 'replace',
                    mealIndex: i,
                  ),
                  onRecipeTap: (r) {
                    ProductAnalytics.logEvent(
                      eventType: 'meal_plan_recipe_open',
                      metadata: {'recipe_id': r.id},
                    );
                    if (r.id != null) {
                      context.push('/recipe/${r.id}');
                    }
                  },
                );
              },
              childCount: day.meals.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanPick {
  const _PlanPick(this.duration, this.familySize);
  final int duration;
  final int familySize;
}
