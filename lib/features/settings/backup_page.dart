import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/user_service.dart';
import '../../utils/api_error_parser.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _isImporting = false;

  Future<Map<String, dynamic>> _buildExport() async {
    return {
      'profile': UserService.instance.exportToJson(),
      'app': {'exportedAt': DateTime.now().toIso8601String()},
    };
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
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано в буфер')),
              );
            },
            child: const Text('Копировать'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromClipboard({required bool merge}) async {
    setState(() => _isImporting = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final jsonStr = data?.text?.trim() ?? '';
      if (jsonStr.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Буфер обмена пуст')),
          );
        }
        return;
      }
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('profile')) {
        await UserService.instance.importFromJson(
          map['profile'] as Map<String, dynamic>,
          merge: merge,
        );
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
            content: Text(
              userVisibleError(e, fallback: 'Не удалось импортировать'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Резервная копия')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Экспорт профиля'),
            subtitle: const Text('Скопировать JSON в буфер'),
            onTap: _showExportDialog,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Импорт (заменить)'),
            subtitle: const Text('Вставить JSON из буфера'),
            onTap: _isImporting
                ? null
                : () => _importFromClipboard(merge: false),
          ),
          ListTile(
            leading: const Icon(Icons.merge_outlined),
            title: const Text('Импорт (объединить)'),
            subtitle: const Text('Вставить JSON из буфера'),
            onTap: _isImporting
                ? null
                : () => _importFromClipboard(merge: true),
          ),
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
