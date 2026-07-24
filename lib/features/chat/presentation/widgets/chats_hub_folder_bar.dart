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
    this.folderUnreadCounts = const {},
  });

  final List<ChatFolder> folders;
  final int? selectedFolderId;
  final ValueChanged<int?> onSelectFolder;
  final VoidCallback onCreateFolder;
  final VoidCallback onManageFolders;
  final ValueChanged<ChatFolder> onFolderLongPress;
  final Map<int, int> folderUnreadCounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        children: [
          _FolderTab(
            label: 'Все',
            selected: selectedFolderId == null,
            onTap: () {
              AppHaptics.selection();
              onSelectFolder(null);
            },
          ),
          for (final folder in folders)
            _FolderTab(
              label: folder.displayLabel,
              selected: selectedFolderId == folder.id,
              unreadCount: folderUnreadCounts[folder.id] ?? 0,
              onTap: () {
                AppHaptics.selection();
                onSelectFolder(folder.id);
              },
              onLongPress: () {
                AppHaptics.medium();
                onFolderLongPress(folder);
              },
            ),
          IconButton(
            tooltip: 'Новая папка',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 20, color: scheme.primary),
            onPressed: () {
              AppHaptics.light();
              onCreateFolder();
            },
          ),
          if (folders.isNotEmpty)
            IconButton(
              tooltip: 'Порядок папок',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.tune_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: onManageFolders,
            ),
        ],
      ),
    );
  }
}

class _FolderTab extends StatelessWidget {
  const _FolderTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.unreadCount = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14.5,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
