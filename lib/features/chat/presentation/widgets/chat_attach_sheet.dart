import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/chat_service.dart';
import 'chats_hub_tiles.dart';

enum ChatAttachTab { gallery, file, poll, contact }

enum ChatAttachResult { galleryFiles, file, poll, contact }

/// Результат выбора вложения с данными.
class ChatAttachSelection {
  const ChatAttachSelection._({
    required this.kind,
    this.galleryFiles = const [],
    this.contact,
  });

  final ChatAttachResult kind;
  final List<XFile> galleryFiles;
  final ChatContact? contact;

  factory ChatAttachSelection.gallery(List<XFile> files) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.galleryFiles,
        galleryFiles: files,
      );

  factory ChatAttachSelection.contact(ChatContact contact) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.contact,
        contact: contact,
      );

  factory ChatAttachSelection.simple(ChatAttachResult kind) =>
      ChatAttachSelection._(kind: kind);
}

/// Панель вложений в стиле Telegram: контент сверху, кружки снизу.
Future<ChatAttachSelection?> showChatAttachSheet(BuildContext context) {
  return showModalBottomSheet<ChatAttachSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChatAttachSheet(),
  );
}

class _ChatAttachSheet extends StatefulWidget {
  const _ChatAttachSheet();

  @override
  State<_ChatAttachSheet> createState() => _ChatAttachSheetState();
}

class _ChatAttachSheetState extends State<_ChatAttachSheet> {
  ChatAttachTab _tab = ChatAttachTab.gallery;
  final _picker = ImagePicker();
  final List<XFile> _gallerySelection = [];
  List<ChatContact> _contacts = [];
  bool _contactsLoading = false;
  String? _contactsError;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _contactsLoading = true;
      _contactsError = null;
    });
    try {
      final items = await ChatService.listContacts();
      if (!mounted) return;
      setState(() {
        _contacts = items;
        _contactsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contactsLoading = false;
        _contactsError = 'Не удалось загрузить контакты';
      });
    }
  }

  Future<void> _addFromGallery() async {
    final files = await _picker.pickMultipleMedia(
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final f in files) {
        if (!_gallerySelection.any((s) => s.path == f.path)) {
          _gallerySelection.add(f);
        }
      }
    });
  }

  Future<void> _capturePhoto() async {
    if (kIsWeb) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() => _gallerySelection.add(file));
  }

  void _close([ChatAttachSelection? result]) => Navigator.pop(context, result);

  String get _headerTitle {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return 'Недавние';
      case ChatAttachTab.file:
        return 'Файл';
      case ChatAttachTab.poll:
        return 'Опрос';
      case ChatAttachTab.contact:
        return 'Контакт';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : theme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _Header(
                title: _headerTitle,
                canSend:
                    _tab == ChatAttachTab.gallery && _gallerySelection.isNotEmpty,
                onClose: () => _close(),
                onSend: () => _close(
                  ChatAttachSelection.gallery(
                    List<XFile>.from(_gallerySelection),
                  ),
                ),
              ),
              Expanded(child: _buildBody(scrollController, isDark)),
              _AttachDock(
                selected: _tab,
                onSelect: (tab) => setState(() => _tab = tab),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController, bool isDark) {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return _GalleryPanel(
          scrollController: scrollController,
          selection: _gallerySelection,
          onAdd: _addFromGallery,
          onCamera: kIsWeb ? null : _capturePhoto,
          onRemove: (i) => setState(() => _gallerySelection.removeAt(i)),
          isDark: isDark,
        );
      case ChatAttachTab.file:
        return _ActionPanel(
          icon: Icons.insert_drive_file_outlined,
          title: 'Отправить файл',
          subtitle: 'Документы, PDF, архивы и другие файлы',
          buttonLabel: 'Выбрать файл',
          onAction: () => _close(ChatAttachSelection.simple(ChatAttachResult.file)),
          isDark: isDark,
        );
      case ChatAttachTab.poll:
        return _ActionPanel(
          icon: Icons.poll_outlined,
          title: 'Создать опрос',
          subtitle: 'Голосование с несколькими вариантами ответа',
          buttonLabel: 'Новый опрос',
          onAction: () => _close(ChatAttachSelection.simple(ChatAttachResult.poll)),
          isDark: isDark,
        );
      case ChatAttachTab.contact:
        return _ContactsPanel(
          scrollController: scrollController,
          contacts: _contacts,
          loading: _contactsLoading,
          error: _contactsError,
          onRetry: _loadContacts,
          onSelect: (c) => _close(ChatAttachSelection.contact(c)),
          isDark: isDark,
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.canSend,
    required this.onClose,
    required this.onSend,
  });

  final String title;
  final bool canSend;
  final VoidCallback onClose;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 22),
            tooltip: 'Закрыть',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (canSend)
            TextButton(onPressed: onSend, child: const Text('Отправить'))
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _GalleryPanel extends StatelessWidget {
  const _GalleryPanel({
    required this.scrollController,
    required this.selection,
    required this.onAdd,
    this.onCamera,
    required this.onRemove,
    required this.isDark,
  });

  final ScrollController scrollController;
  final List<XFile> selection;
  final VoidCallback onAdd;
  final VoidCallback? onCamera;
  final ValueChanged<int> onRemove;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    if (onCamera != null) {
      cells.add(_GalleryAddTile(
        icon: Icons.photo_camera_outlined,
        onTap: onCamera!,
        isDark: isDark,
      ));
    }
    cells.add(_GalleryAddTile(
      icon: Icons.photo_library_outlined,
      onTap: onAdd,
      isDark: isDark,
    ));
    for (var i = 0; i < selection.length; i++) {
      cells.add(_GalleryThumb(
        file: selection[i],
        onTap: () => onRemove(i),
        isDark: isDark,
      ));
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: cells.length,
      itemBuilder: (_, i) => cells[i],
    );
  }
}

class _GalleryAddTile extends StatelessWidget {
  const _GalleryAddTile({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? const Color(0xFF2C2C2E)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({
    required this.file,
    required this.onTap,
    required this.isDark,
  });

  final XFile file;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (kIsWeb)
          Container(color: const Color(0xFF3A3A3C))
        else
          Image.file(File(file.path), fit: BoxFit.cover),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onAction,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onAction;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class _ContactsPanel extends StatelessWidget {
  const _ContactsPanel({
    required this.scrollController,
    required this.contacts,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onSelect,
    required this.isDark,
  });

  final ScrollController scrollController;
  final List<ChatContact> contacts;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<ChatContact> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (contacts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет контактов.\nДобавьте людей в разделе «Контакты».',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final contact = contacts[i];
        return ListTile(
          leading: ChatHubUserAvatar(user: contact.user),
          title: Text(contact.user.displayName),
          subtitle: contact.user.username != null
              ? Text('@${contact.user.username}')
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () => onSelect(contact),
        );
      },
    );
  }
}

class _AttachDock extends StatelessWidget {
  const _AttachDock({
    required this.selected,
    required this.onSelect,
  });

  final ChatAttachTab selected;
  final ValueChanged<ChatAttachTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DockItem(
                icon: Icons.photo_library_outlined,
                label: 'Галерея',
                selected: selected == ChatAttachTab.gallery,
                onTap: () => onSelect(ChatAttachTab.gallery),
              ),
              _DockItem(
                icon: Icons.insert_drive_file_outlined,
                label: 'Файл',
                selected: selected == ChatAttachTab.file,
                onTap: () => onSelect(ChatAttachTab.file),
              ),
              _DockItem(
                icon: Icons.poll_outlined,
                label: 'Опрос',
                selected: selected == ChatAttachTab.poll,
                onTap: () => onSelect(ChatAttachTab.poll),
              ),
              _DockItem(
                icon: Icons.person_outline,
                label: 'Контакт',
                selected: selected == ChatAttachTab.contact,
                onTap: () => onSelect(ChatAttachTab.contact),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected
                    ? (isDark
                        ? const Color(0xFF3A3A3C)
                        : theme.colorScheme.primaryContainer)
                    : (isDark
                        ? const Color(0xFF2C2C2E)
                        : theme.colorScheme.surfaceContainerHighest),
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                size: 26,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
