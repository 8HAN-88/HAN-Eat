import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../subscription/presentation/widgets/nutrition_upsell.dart';

class DietScreen extends ConsumerStatefulWidget {
  const DietScreen({super.key});

  @override
  ConsumerState<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends ConsumerState<DietScreen> {
  final Map<String, bool> _diets = {
    'Вегетарианская': false,
    'Веганская': false,
    'Палео': false,
    'Кето': false,
    'Без глютена': false,
    'Низкоуглеводная': false,
    'Средиземноморская': false,
  };
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _caloriesPerDishController = TextEditingController();
  final TextEditingController _fatPerDishController = TextEditingController();
  final TextEditingController _carbsPerDishController = TextEditingController();
  final TextEditingController _proteinPerDishController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAccess());
    _loadSettings();
  }

  Future<void> _checkAccess() async {
    if (!mounted) return;
    if (ref.read(canViewRecipeNutritionProvider)) return;
    await showNutritionUpsellSheet(context);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _calorieController.dispose();
    _caloriesPerDishController.dispose();
    _fatPerDishController.dispose();
    _carbsPerDishController.dispose();
    _proteinPerDishController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _diets.keys) {
        _diets[key] = prefs.getBool('diet_$key') ?? false;
      }
      final daily = prefs.getInt('calorie_limit');
      if (daily != null) _calorieController.text = daily.toString();
      final cpd = prefs.getInt('max_calories_per_dish');
      if (cpd != null) _caloriesPerDishController.text = cpd.toString();
      final fpd = prefs.getInt('max_fat_per_dish_g');
      if (fpd != null) _fatPerDishController.text = fpd.toString();
      final carbpd = prefs.getInt('max_carbs_per_dish_g');
      if (carbpd != null) _carbsPerDishController.text = carbpd.toString();
      final ppd = prefs.getInt('max_protein_per_dish_g');
      if (ppd != null) _proteinPerDishController.text = ppd.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in _diets.entries) {
        await prefs.setBool('diet_${e.key}', e.value);
      }
      final calText = _calorieController.text.trim();
      if (calText.isNotEmpty) {
        final v = int.tryParse(calText);
        if (v != null && v > 0) {
          await prefs.setInt('calorie_limit', v);
        } else {
          await prefs.remove('calorie_limit');
        }
      } else {
        await prefs.remove('calorie_limit');
      }
      await _saveInt(prefs, 'max_calories_per_dish', _caloriesPerDishController.text);
      await _saveInt(prefs, 'max_fat_per_dish_g', _fatPerDishController.text);
      await _saveInt(prefs, 'max_carbs_per_dish_g', _carbsPerDishController.text);
      await _saveInt(prefs, 'max_protein_per_dish_g', _proteinPerDishController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки диеты сохранены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInt(SharedPreferences prefs, String key, String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final v = int.tryParse(t);
    if (v != null && v >= 0) await prefs.setInt(key, v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Диета')),
      body: _loading && _diets.values.every((v) => !v)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + floatingBottomPadding(context),
              ),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Лимиты на одно блюдо', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _numberField('Макс. калории', 'ккал', _caloriesPerDishController, '500'),
                        const SizedBox(height: 10),
                        _numberField('Макс. жиры', 'г', _fatPerDishController, '30'),
                        const SizedBox(height: 10),
                        _numberField('Макс. углеводы', 'г', _carbsPerDishController, '50'),
                        const SizedBox(height: 10),
                        _numberField('Макс. белки', 'г', _proteinPerDishController, '40'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Дневной лимит калорий', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _calorieController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Например: 2000',
                            suffixText: 'ккал',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text('Тип диеты', style: theme.textTheme.titleMedium),
                      ),
                      ..._diets.entries.map((e) => SwitchListTile(
                            title: Text(e.key),
                            value: e.value,
                            onChanged: (v) => setState(() => _diets[e.key] = v),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _saveSettings,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
    );
  }

  Widget _numberField(String label, String suffix, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
