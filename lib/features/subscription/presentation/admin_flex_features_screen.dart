import 'package:flutter/material.dart';

import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';

class AdminFlexFeaturesScreen extends StatefulWidget {
  const AdminFlexFeaturesScreen({super.key});

  @override
  State<AdminFlexFeaturesScreen> createState() => _AdminFlexFeaturesScreenState();
}

class _AdminFlexFeaturesScreenState extends State<AdminFlexFeaturesScreen> {
  FlexAdminCatalog? _catalog;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await FlexSubscriptionApi.adminCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
  }

  Future<void> _edit(FlexFeature? feature) async {
    final title = TextEditingController(text: feature?.title ?? '');
    final slug = TextEditingController(text: feature?.slug ?? '');
    final description = TextEditingController(text: feature?.description ?? '');
    final icon = TextEditingController(text: feature?.icon ?? '');
    var type = feature?.featureType ?? 'movable';
    var minLevel = feature?.minLevel ?? 1;
    var maxLevel = feature?.maxLevel ?? 3;
    var defaultLevel = feature?.assignedLevel ?? 1;
    var movable = feature?.movable ?? true;
    var required = feature?.required ?? false;
    var blockKey = feature?.blockKey ?? 'A';
    var available = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(feature == null ? 'Новая функция' : 'Редактировать'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
                TextField(controller: slug, decoration: const InputDecoration(labelText: 'slug')),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Описание')),
                TextField(controller: icon, decoration: const InputDecoration(labelText: 'Иконка')),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                    DropdownMenuItem(value: 'movable', child: Text('Movable')),
                    DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                    DropdownMenuItem(value: 'premium', child: Text('Premium')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                DropdownButtonFormField<String>(
                  value: blockKey,
                  decoration: const InputDecoration(labelText: 'Блок'),
                  items: [
                    for (final b in _catalog?.blocks ?? const <FlexBlock>[])
                      DropdownMenuItem(value: b.key, child: Text('${b.key} · ${b.title}')),
                  ],
                  onChanged: (v) => setLocal(() => blockKey = v ?? blockKey),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: '$minLevel',
                        decoration: const InputDecoration(labelText: 'min'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => minLevel = int.tryParse(v) ?? minLevel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '$maxLevel',
                        decoration: const InputDecoration(labelText: 'max'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => maxLevel = int.tryParse(v) ?? maxLevel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '$defaultLevel',
                        decoration: const InputDecoration(labelText: 'уровень'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => defaultLevel = int.tryParse(v) ?? defaultLevel,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Можно перемещать'),
                  value: movable,
                  onChanged: (v) => setLocal(() => movable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Обязательная'),
                  value: required,
                  onChanged: (v) => setLocal(() => required = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Доступна'),
                  value: available,
                  onChanged: (v) => setLocal(() => available = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    final payload = {
      'title': title.text.trim(),
      'slug': slug.text.trim(),
      'description': description.text.trim(),
      'icon': icon.text.trim(),
      'feature_type': type,
      'min_level': minLevel,
      'max_level': maxLevel,
      'default_level': defaultLevel,
      'movable': movable,
      'required': required,
      'block_key': blockKey,
      'available': available,
      'status': 'active',
    };
    title.dispose();
    slug.dispose();
    description.dispose();
    icon.dispose();
    if (ok != true) return;
    try {
      await FlexSubscriptionApi.adminSaveFeature(payload, id: feature?.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Функции подписки')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: AppGradientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    children: [
                      for (final block in _catalog!.blocks) ...[
                        Text(
                          'Блок ${block.key} · ${block.title} (${block.minLevel}–${block.maxLevel})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        for (final feature in _catalog!.features.where((f) => f.blockKey == block.key))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(feature.title),
                            subtitle: Text(
                              '${feature.slug} · ${feature.featureType} · ур. ${feature.assignedLevel}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(feature),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
      ),
    );
  }
}
