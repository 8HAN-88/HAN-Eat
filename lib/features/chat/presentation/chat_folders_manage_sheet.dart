import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_folder_store.dart';

/// Перетаскивание папок для изменения порядка вкладок.
class ChatFoldersManageSheet extends StatefulWidget {
  const ChatFoldersManageSheet({
    super.key,
    required this.folders,
  });

  final List<ChatFolder> folders;

  @override
  State<ChatFoldersManageSheet> createState() => _ChatFoldersManageSheetState();
}

class _ChatFoldersManageSheetState extends State<ChatFoldersManageSheet> {
  late List<ChatFolder> _folders;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _folders = [...widget.folders];
  }

  Future<void> _saveOrder() async {
    setState(() => _saving = true);
    try {
      final ids = _folders.map((f) => f.id).toList();
      final updated = await ChatFolderStore.reorderFolders(ids);
      if (!mounted) return;
      Navigator.pop(context, updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Порядок папок',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _saveOrder,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Готово'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _folders.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _folders.removeAt(oldIndex);
                  _folders.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final folder = _folders[index];
                return ListTile(
                  key: ValueKey('folder_manage_${folder.id}'),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(folder.displayLabel),
                  subtitle: Text(
                    '${folder.conversationIds.length} чатов · '
                    '${folder.channelIds.length} каналов',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
