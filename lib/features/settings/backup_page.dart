import 'dart:convert';
import '../../utils/api_error_parser.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/user_service.dart';
import '../../services/favorites_service.dart';
import '../../services/shopping_service.dart';
import '../../services/recipe_notes_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _isImporting = false;

  Future<Map<String, dynamic>> _buildExport() async {
    final Map<String, dynamic> out = {};
    final up = UserService.instance.exportToJson();
    out['profile'] = up;
    out['favorites'] = FavoritesService.instance.exportToJson();
    out['shopping'] = ShoppingService.instance.exportToJson();
    out['recipe_notes'] = await RecipeNotesService.exportToJson();
    out['app'] = {'exportedAt': DateTime.now().toIso8601String()};
    return out;
  }

  Future<void> _showExportDialog() async {
    final map = await _buildExport();
    if (!mounted) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Резервная копия'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(jsonStr),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON скопирован в буфер обмена')),
              );
            },
            child: const Text('Копировать'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    var merge = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setState) {
          return AlertDialog(
            title: const Text('Восстановление из JSON'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вставьте JSON из ранее сохранённой копии.',
                    style: Theme.of(c).textTheme.bodySmall?.copyWith(
                          color: Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      hintText: 'Вставьте JSON сюда',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: merge,
                    onChanged: (v) => setState(() => merge = v ?? true),
                    title: const Text('Объединить с текущими данными'),
                    subtitle: const Text(
                      'Сохранить существующее и добавить из файла',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Вставьте JSON для импорта')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  await _performImport(text, merge: merge);
                },
                child: const Text('Импортировать'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _performImport(String jsonStr, {bool merge = true}) async {
    setState(() => _isImporting = true);
    try {
      final Map<String, dynamic> map =
          json.decode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('profile')) {
        try {
          await UserService.instance.importFromJson(
            map['profile'] as Map<String, dynamic>,
            merge: merge,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  userVisibleError(e, fallback: 'Не удалось импортировать профиль'),
                ),
              ),
            );
          }
        }
      }
      if (map.containsKey('favorites')) {
        try {
          final favMap = map['favorites'] as Map<String, dynamic>;
          await FavoritesService.instance.importFromJson(favMap, merge: merge);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  userVisibleError(e, fallback: 'Не удалось импортировать избранное'),
                ),
              ),
            );
          }
        }
      }
      if (map.containsKey('shopping')) {
        try {
          final shopMap = map['shopping'] as Map<String, dynamic>;
          await ShoppingService.instance.importFromJson(shopMap, merge: merge);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  userVisibleError(
                    e,
                    fallback: 'Не удалось импортировать список покупок',
                  ),
                ),
              ),
            );
          }
        }
      }
      if (map.containsKey('recipe_notes')) {
        try {
          final notesMap = map['recipe_notes'] as Map<String, dynamic>;
          await RecipeNotesService.importFromJson(notesMap, merge: merge);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  userVisibleError(e, fallback: 'Не удалось импортировать заметки'),
                ),
              ),
            );
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Импорт завершён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userVisibleError(e, fallback: 'Некорректный JSON')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Резервная копия')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Экспортируйте избранное, список покупок и заметки в JSON. '
            'Сохраните файл в облаке или отправьте себе — так данные не потеряются при смене устройства.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.download_rounded),
            label: const Text('Экспорт (скопировать JSON)'),
            onPressed: _showExportDialog,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Импорт из JSON'),
            onPressed: _isImporting ? null : _showImportDialog,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (_isImporting) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Импорт данных…',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
