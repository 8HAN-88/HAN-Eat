import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AllergiesScreen extends StatefulWidget {
  const AllergiesScreen({super.key});

  @override
  State<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends State<AllergiesScreen> {
  final Map<String, bool> _standardAllergies = {
    'Молочные продукты': false,
    'Яйца': false,
    'Рыба': false,
    'Морепродукты': false,
    'Орехи': false,
    'Арахис': false,
    'Пшеница': false,
    'Соя': false,
    'Кунжут': false,
  };
  final Map<String, String> _customAllergies = {};
  int _customAllergyCounter = 0;
  final Map<String, TextEditingController> _customAllergyControllers = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in _customAllergyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCustomAllergy() {
    setState(() {
      final key = 'custom_${_customAllergyCounter++}';
      _customAllergies[key] = '';
      _customAllergyControllers[key] = TextEditingController();
    });
  }

  void _removeCustomAllergy(String key) {
    final controller = _customAllergyControllers[key];
    setState(() {
      _customAllergies.remove(key);
      _customAllergyControllers.remove(key);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => controller?.dispose());
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _standardAllergies.keys) {
        _standardAllergies[key] = prefs.getBool('allergy_$key') ?? false;
      }
      final customJson = prefs.getStringList('custom_allergies') ?? [];
      _customAllergies.clear();
      _customAllergyControllers.clear();
      _customAllergyCounter = 0;
      for (final allergy in customJson) {
        final key = 'custom_${_customAllergyCounter++}';
        _customAllergies[key] = allergy;
        _customAllergyControllers[key] = TextEditingController(text: allergy);
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in _standardAllergies.entries) {
        await prefs.setBool('allergy_${e.key}', e.value);
      }
      final valid = <String>[];
      for (final e in _customAllergies.entries) {
        final t = _customAllergyControllers[e.key]?.text.trim() ?? e.value.trim();
        if (t.isNotEmpty) {
          valid.add(t);
          _customAllergies[e.key] = t;
        }
      }
      await prefs.setStringList('custom_allergies', valid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки аллергий сохранены')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Аллергии')),
      body: _loading && _standardAllergies.values.every((v) => !v) && _customAllergies.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + floatingBottomPadding(context),
              ),
              children: [
                Text(
                  'Исключите продукты, которые вам нельзя',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: _standardAllergies.entries.map((e) => SwitchListTile(
                          title: Text(e.key),
                          value: e.value,
                          onChanged: (v) => setState(() => _standardAllergies[e.key] = v),
                        )).toList(),
                  ),
                ),
                if (_customAllergies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        for (final e in _customAllergies.entries)
                          Padding(
                            key: ValueKey(e.key),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customAllergyControllers[e.key],
                                    decoration: const InputDecoration(
                                      hintText: 'Свой аллерген',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => _customAllergies[e.key] = v,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                  color: theme.colorScheme.error,
                                  onPressed: () => _removeCustomAllergy(e.key),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Добавить свой аллерген'),
                  onPressed: _addCustomAllergy,
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
}
