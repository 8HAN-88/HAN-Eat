import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/nutrition_prefs_service.dart';

/// Шаг онбординга: цель по калориям и тип питания.
class OnboardingNutritionPage extends StatefulWidget {
  const OnboardingNutritionPage({super.key});

  @override
  State<OnboardingNutritionPage> createState() => OnboardingNutritionPageState();
}

class OnboardingNutritionPageState extends State<OnboardingNutritionPage> {
  final _calorieController = TextEditingController(text: '2000');
  final _selectedDiets = <String>{};
  bool _allowMealRepeats = true;
  int _repeatIntervalDays = 4;

  static const _dietOptions = [
    'Средиземноморская',
    'Вегетарианская',
    'Кето',
    'Без глютена',
  ];

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final data = await NutritionPrefsService.loadSurveyData();
    if (!mounted) return;
    setState(() {
      if (data.calories != null) {
        _calorieController.text = '${data.calories}';
      }
      _selectedDiets
        ..clear()
        ..addAll(data.diets);
      _allowMealRepeats = data.allowMealRepeats;
      _repeatIntervalDays = data.mealRepeatIntervalDays;
    });
  }

  @override
  void dispose() {
    _calorieController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final cal = int.tryParse(_calorieController.text.trim());
    await NutritionPrefsService.saveOnboardingNutrition(
      calories: cal,
      diets: _selectedDiets.toList(),
      allowMealRepeats: _allowMealRepeats,
      mealRepeatIntervalDays: _repeatIntervalDays,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
          Icon(Icons.monitor_heart_outlined, size: 80, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            'Ваши цели питания',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'AI-план подстроится под калории и предпочтения. Настройки можно изменить в профиле.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _calorieController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Калории в день',
              suffixText: 'ккал',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Стиль питания', style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _dietOptions.map((d) {
              final selected = _selectedDiets.contains(d);
              return FilterChip(
                label: Text(d),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedDiets.add(d);
                    } else {
                      _selectedDiets.remove(d);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Повторение блюд', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Разрешить повторы'),
            subtitle: const Text('Иначе — только уникальные блюда в плане'),
            value: _allowMealRepeats,
            onChanged: (v) => setState(() => _allowMealRepeats = v),
          ),
          if (_allowMealRepeats)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: NutritionPrefsService.mealRepeatIntervalOptions.map((d) {
                return FilterChip(
                  label: Text('$d дн.'),
                  selected: _repeatIntervalDays == d,
                  onSelected: (_) => setState(() => _repeatIntervalDays = d),
                );
              }).toList(),
            ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
