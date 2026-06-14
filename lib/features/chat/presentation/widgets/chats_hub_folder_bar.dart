import 'package:flutter/material.dart';

import '../../../../core/haptics/app_haptics.dart';
import '../../../../models/chat_models.dart';

class ChatHubFolderBar extends StatelessWidget {
  const ChatHubFolderBar({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelectFolder,
    required this.onCreateFolder,
    required this.onManageFolders,
    required this.onFolderLongPress,
  });

  final List<ChatFolder> folders;
  final int? selectedFolderId;
  final ValueChanged<int?> onSelectFolder;
  final VoidCallback onCreateFolder;
  final VoidCallback onManageFolders;
  final ValueChanged<ChatFolder> onFolderLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Все чаты'),
              selected: selectedFolderId == null,
              onSelected: (_) {
                AppHaptics.selection();
                onSelectFolder(null);
              },
            ),
          ),
          for (final folder in folders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () {
                  AppHaptics.medium();
                  onFolderLongPress(folder);
                },
                child: FilterChip(
                  label: Text(folder.displayLabel),
                  selected: selectedFolderId == folder.id,
                  onSelected: (_) {
                    AppHaptics.selection();
                    onSelectFolder(folder.id);
                  },
                ),
              ),
            ),
          ActionChip(
            avatar: Icon(Icons.add, size: 18, color: scheme.primary),
            label: const Text('Папка'),
            onPressed: () {
              AppHaptics.light();
              onCreateFolder();
            },
          ),
          if (folders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                tooltip: 'Порядок папок',
                icon: const Icon(Icons.sort),
                onPressed: onManageFolders,
              ),
            ),
        ],
      ),
    );
  }
}
