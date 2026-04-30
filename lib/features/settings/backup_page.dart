import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/user_service.dart';
import '../../services/favorites_service.dart';
import '../../services/shopping_service.dart';
import '../../services/recipe_notes_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({Key? key}) : super(key: key);

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _isImporting = false;

  Future<Map<String, dynamic>> _buildExport() async {
    final Map<String, dynamic> out = {};
    final up = UserService.instance.exportToJson();
    if (up != null) out['profile'] = up;
    out['favorites'] = FavoritesService.instance.exportToJson();
    out['shopping'] = ShoppingService.instance.exportToJson();
    out['recipe_notes'] = await RecipeNotesService.exportToJson();
    out['app'] = {'exportedAt': DateTime.now().toIso8601String()};
    return out;
  }

  Future<void> _showExportDialog() async {
    final map = await _buildExport();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Backup'),
        content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(jsonStr))),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON copied to clipboard')));
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    bool merge = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (c, setState) {
        return AlertDialog(
          title: const Text('Import Backup (paste JSON)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: const InputDecoration(
                      hintText: 'Paste exported JSON here'),
                ),
                Row(
                  children: [
                    Checkbox(
                        value: merge,
                        onChanged: (v) => setState(() => merge = v ?? true)),
                    const SizedBox(width: 8),
                    const Text(
                        'Merge with existing (keep existing + incoming)'),
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No JSON provided')));
                  return;
                }
                Navigator.of(ctx).pop();
                await _performImport(text, merge: merge);
              },
              child: const Text('Import'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _performImport(String jsonStr, {bool merge = true}) async {
    setState(() => _isImporting = true);
    try {
      final Map<String, dynamic> map =
          json.decode(jsonStr) as Map<String, dynamic>;
      // profile
      if (map.containsKey('profile')) {
        try {
          await UserService.instance.importFromJson(
              map['profile'] as Map<String, dynamic>,
              merge: merge);
        } catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Profile import failed: $e')));
        }
      }
      // favorites
      if (map.containsKey('favorites')) {
        try {
          final favMap = map['favorites'] as Map<String, dynamic>;
          await FavoritesService.instance.importFromJson(favMap, merge: merge);
        } catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Favorites import failed: $e')));
        }
      }
      // shopping
      if (map.containsKey('shopping')) {
        try {
          final shopMap = map['shopping'] as Map<String, dynamic>;
          await ShoppingService.instance.importFromJson(shopMap, merge: merge);
        } catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Shopping import failed: $e')));
        }
      }
      // recipe notes
      if (map.containsKey('recipe_notes')) {
        try {
          final notesMap = map['recipe_notes'] as Map<String, dynamic>;
          await RecipeNotesService.importFromJson(notesMap, merge: merge);
        } catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Recipe notes import failed: $e')));
        }
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Import completed')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
    } finally {
      setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export Backup (copy JSON)'),
              onPressed: _showExportDialog,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Import Backup (paste JSON)'),
              onPressed: _showImportDialog,
            ),
            if (_isImporting)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
            const SizedBox(height: 24),
            const Text(
                'Tip: you can copy the exported JSON to a file or cloud storage as a manual backup.'),
          ],
        ),
      ),
    );
  }
}
