import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/chat_service.dart';
import '../../application/chat_recent_files_store.dart';
import 'chat_poll_form_panel.dart';
import 'chats_hub_tiles.dart';
import 'create_chat_poll_sheet.dart';

enum ChatAttachTab { gallery, file, poll, contact }

enum ChatAttachResult {
  galleryFiles,
  file,
  pickedFile,
  poll,
  contact,
  resendFile,
}

class ChatAttachSelection {
  const ChatAttachSelection._({
    required this.kind,
    this.galleryFiles = const [],
    this.contact,
    this.pollDraft,
    this.resendFileName,
    this.resendFileUrl,
    this.pickedFile,
    this.pickedFileName,
  });

  final ChatAttachResult kind;
  final List<XFile> galleryFiles;
  final ChatContact? contact;
  final ChatPollDraft? pollDraft;
  final String? resendFileName;
  final String? resendFileUrl;
  final XFile? pickedFile;
  final String? pickedFileName;

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

  factory ChatAttachSelection.pollDraft(ChatPollDraft draft) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.poll,
        pollDraft: draft,
      );

  factory ChatAttachSelection.resendFile({
    required String name,
    required String mediaUrl,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.resendFile,
        resendFileName: name,
        resendFileUrl: mediaUrl,
      );

  factory ChatAttachSelection.pickedFile({
    required XFile file,
    required String name,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.pickedFile,
        pickedFile: file,
        pickedFileName: name,
      );
}

Future<ChatAttachSelection?> showChatAttachSheet(BuildContext context) {
  return showModalBottomSheet<ChatAttachSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: false,
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
  final _pollFormKey = GlobalKey<ChatPollFormPanelState>();
  final _searchController = TextEditingController();

  final List<XFile> _gallerySelection = [];
  List<ChatContact> _contacts = [];
  List<ChatRecentFileEntry> _recentFiles = [];
  bool _contactsLoading = false;
  bool _recentLoading = true;
  String? _contactsError;
  bool _pollCanSend = false;
  bool _searchVisible = false;
  String _searchQuery = '';

  static const _sheetBgDark = Color(0xFF1C1C1E);
  static const _groupBgDark = Color(0xFF2C2C2E);
  static const _telegramBlue = Color(0xFF007AFF);

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadRecentFiles();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _loadRecentFiles() async {
    final items = await ChatRecentFilesStore.load();
    if (!mounted) return;
    setState(() {
      _recentFiles = items;
      _recentLoading = false;
    });
  }

  void _close([ChatAttachSelection? result]) => Navigator.pop(context, result);

  void _setTab(ChatAttachTab tab) {
    setState(() {
      _tab = tab;
      _searchVisible = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  String get _headerTitle {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return 'Недавние';
      case ChatAttachTab.file:
        return 'Файл';
      case ChatAttachTab.poll:
        return 'Новый опрос';
      case ChatAttachTab.contact:
        return 'Контакты';
    }
  }

  bool get _showSearch =>
      _tab == ChatAttachTab.file || _tab == ChatAttachTab.contact;

  bool get _showGallerySend =>
      _tab == ChatAttachTab.gallery && _gallerySelection.isNotEmpty;

  bool get _showPollSend => _tab == ChatAttachTab.poll;

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

  Future<void> _pickDocument({bool scan = false}) async {
    if (scan && !kIsWeb) {
      final scanned = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (scanned != null && mounted) {
        _close(ChatAttachSelection.gallery([scanned]));
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'txt',
        'doc',
        'docx',
        'zip',
        'jpg',
        'jpeg',
        'png',
        'heic',
      ],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.single;
    final XFile file;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) return;
      file = XFile.fromData(bytes, name: picked.name);
    } else {
      final path = picked.path;
      if (path == null || path.isEmpty) return;
      file = XFile(path);
    }
    _close(
      ChatAttachSelection.pickedFile(file: file, name: picked.name),
    );
  }

  void _sendPoll() {
    final draft = _pollFormKey.currentState?.buildDraft();
    if (draft == null) return;
    _close(ChatAttachSelection.pollDraft(draft));
  }

  List<ChatContact> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = c.user.displayName.toLowerCase();
      final username = c.user.username?.toLowerCase() ?? '';
      return name.contains(_searchQuery) || username.contains(_searchQuery);
    }).toList();
  }

  List<ChatRecentFileEntry> get _filteredRecentFiles {
    if (_searchQuery.isEmpty) return _recentFiles;
    return _recentFiles
        .where((f) => f.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? _sheetBgDark : theme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.45,
      maxChildSize: 0.94,
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
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _TelegramHeader(
                title: _headerTitle,
                showSearch: _showSearch,
                showSend: _showGallerySend || _showPollSend,
                sendEnabled: _showPollSend ? _pollCanSend : true,
                onClose: () => _close(),
                onSearch: _toggleSearch,
                onSend: () {
                  if (_showPollSend) {
                    _sendPoll();
                  } else {
                    _close(
                      ChatAttachSelection.gallery(
                        List<XFile>.from(_gallerySelection),
                      ),
                    );
                  }
                },
              ),
              if (_searchVisible && _showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Поиск',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: isDark ? _groupBgDark : theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              Expanded(
                child: _buildBody(scrollController, isDark),
              ),
              _TelegramAttachDock(
                selected: _tab,
                onSelect: _setTab,
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
        return _FilePanel(
          scrollController: scrollController,
          recentFiles: _filteredRecentFiles,
          loading: _recentLoading,
          isDark: isDark,
          onPickGallery: () => _setTab(ChatAttachTab.gallery),
          onPickFiles: () => _pickDocument(),
          onScanDocument: () => _pickDocument(scan: true),
          onRecentTap: (entry) {
            final url = entry.mediaUrl;
            if (url != null && url.isNotEmpty) {
              _close(
                ChatAttachSelection.resendFile(
                  name: entry.name,
                  mediaUrl: url,
                ),
              );
            } else {
              _pickDocument();
            }
          },
        );
      case ChatAttachTab.poll:
        return ChatPollFormPanel(
          key: _pollFormKey,
          scrollController: scrollController,
          onValidityChanged: (v) {
            if (_pollCanSend != v) setState(() => _pollCanSend = v);
          },
        );
      case ChatAttachTab.contact:
        return _ContactsPanel(
          scrollController: scrollController,
          contacts: _filteredContacts,
          loading: _contactsLoading,
          error: _contactsError,
          onRetry: _loadContacts,
          onSelect: (c) => _close(ChatAttachSelection.contact(c)),
          isDark: isDark,
        );
    }
  }
}

class _TelegramHeader extends StatelessWidget {
  const _TelegramHeader({
    required this.title,
    required this.showSearch,
    required this.showSend,
    required this.sendEnabled,
    required this.onClose,
    required this.onSearch,
    required this.onSend,
  });

  final String title;
  final bool showSearch;
  final bool showSend;
  final bool sendEnabled;
  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
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
          if (showSend)
            FilledButton(
              onPressed: sendEnabled ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: sendEnabled
                    ? _ChatAttachSheetState._telegramBlue
                    : theme.colorScheme.surfaceContainerHighest,
                foregroundColor: sendEnabled
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Отправить'),
            )
          else if (showSearch)
            IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.search, size: 22),
              tooltip: 'Поиск',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _FilePanel extends StatelessWidget {
  const _FilePanel({
    required this.scrollController,
    required this.recentFiles,
    required this.loading,
    required this.isDark,
    required this.onPickGallery,
    required this.onPickFiles,
    required this.onScanDocument,
    required this.onRecentTap,
  });

  final ScrollController scrollController;
  final List<ChatRecentFileEntry> recentFiles;
  final bool loading;
  final bool isDark;
  final VoidCallback onPickGallery;
  final VoidCallback onPickFiles;
  final VoidCallback onScanDocument;
  final ValueChanged<ChatRecentFileEntry> onRecentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupBg = isDark
        ? _ChatAttachSheetState._groupBgDark
        : theme.colorScheme.surfaceContainerHighest;
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: [
        _GroupedSurface(
          color: groupBg,
          children: [
            _FileActionTile(
              icon: Icons.photo_outlined,
              label: 'Выбрать из Галереи',
              onTap: onPickGallery,
            ),
            _divider(theme),
            _FileActionTile(
              icon: Icons.cloud_outlined,
              label: 'Выбрать из файлов',
              onTap: onPickFiles,
            ),
            if (!kIsWeb) ...[
              _divider(theme),
              _FileActionTile(
                icon: Icons.document_scanner_outlined,
                label: 'Сканировать документ',
                onTap: onScanDocument,
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'НЕДАВНО ОТПРАВЛЕННЫЕ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (recentFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Здесь появятся недавно отправленные файлы',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _GroupedSurface(
            color: groupBg,
            children: [
              for (var i = 0; i < recentFiles.length; i++) ...[
                if (i > 0) _divider(theme),
                _RecentFileTile(
                  entry: recentFiles[i],
                  dateLabel: dateFmt.format(recentFiles[i].sentAt),
                  onTap: () => onRecentTap(recentFiles[i]),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _divider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 52,
      color: theme.dividerColor.withValues(alpha: 0.2),
    );
  }
}

class _FileActionTile extends StatelessWidget {
  const _FileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: Icon(icon, color: _ChatAttachSheetState._telegramBlue, size: 24),
      title: Text(
        label,
        style: const TextStyle(
          color: _ChatAttachSheetState._telegramBlue,
          fontSize: 17,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _RecentFileTile extends StatelessWidget {
  const _RecentFileTile({
    required this.entry,
    required this.dateLabel,
    required this.onTap,
  });

  final ChatRecentFileEntry entry;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = entry.name.contains('.')
        ? entry.name.split('.').last.toUpperCase()
        : 'FILE';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _fileThumbColor(ext),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          ext.length <= 4 ? ext : 'DOC',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${formatChatFileSize(entry.sizeBytes)} · $dateLabel',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }

  Color _fileThumbColor(String ext) {
    switch (ext) {
      case 'ZIP':
      case 'RAR':
        return const Color(0xFFFF9500);
      case 'PDF':
        return const Color(0xFFFF3B30);
      case 'PNG':
      case 'JPG':
      case 'JPEG':
      case 'HEIC':
        return const Color(0xFF34C759);
      default:
        return const Color(0xFF007AFF);
    }
  }
}

class _GroupedSurface extends StatelessWidget {
  const _GroupedSurface({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
          ? _ChatAttachSheetState._groupBgDark
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

    final grouped = _groupContacts(contacts);
    final letters = grouped.keys.toList()..sort(_letterSort);

    return Stack(
      children: [
        ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 28, 8),
          itemCount: letters.length,
          itemBuilder: (context, sectionIndex) {
            final letter = letters[sectionIndex];
            final sectionContacts = grouped[letter]!;
            final groupBg = isDark
                ? _ChatAttachSheetState._groupBgDark
                : Theme.of(context).colorScheme.surfaceContainerHighest;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                  child: Text(
                    letter,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _GroupedSurface(
                  color: groupBg,
                  children: [
                    for (var i = 0; i < sectionContacts.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 68,
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.2),
                        ),
                      _ContactTile(
                        contact: sectionContacts[i],
                        onTap: () => onSelect(sectionContacts[i]),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
        Positioned(
          right: 4,
          top: 8,
          bottom: 8,
          child: _AlphabetRail(letters: letters),
        ),
      ],
    );
  }

  Map<String, List<ChatContact>> _groupContacts(List<ChatContact> items) {
    final map = <String, List<ChatContact>>{};
    for (final contact in items) {
      final name = contact.user.displayName.trim();
      final first = name.isNotEmpty ? name[0].toUpperCase() : '#';
      final key = RegExp(r'[A-ZА-ЯЁ]', caseSensitive: false).hasMatch(first)
          ? first
          : '#';
      map.putIfAbsent(key, () => []).add(contact);
    }
    for (final list in map.values) {
      list.sort(
        (a, b) => a.user.displayName
            .toLowerCase()
            .compareTo(b.user.displayName.toLowerCase()),
      );
    }
    return map;
  }

  int _letterSort(String a, String b) {
    if (a == '#') return 1;
    if (b == '#') return -1;
    return a.compareTo(b);
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final ChatContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = contact.user.username != null
        ? '@${contact.user.username}'
        : 'в списке контактов';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: ChatHubUserAvatar(user: contact.user),
      title: Text(
        contact.user.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _AlphabetRail extends StatelessWidget {
  const _AlphabetRail({required this.letters});

  final List<String> letters;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final letter in letters)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              letter,
              style: const TextStyle(
                color: _ChatAttachSheetState._telegramBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _TelegramAttachDock extends StatelessWidget {
  const _TelegramAttachDock({
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
        color: isDark ? _ChatAttachSheetState._sheetBgDark : theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected
                      ? _ChatAttachSheetState._telegramBlue
                          .withValues(alpha: isDark ? 0.22 : 0.14)
                      : (isDark
                          ? _ChatAttachSheetState._groupBgDark
                          : theme.colorScheme.surfaceContainerHighest),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: selected
                      ? _ChatAttachSheetState._telegramBlue
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? _ChatAttachSheetState._telegramBlue
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
