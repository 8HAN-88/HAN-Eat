import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/channel_service.dart';
import '../../../services/chat_folder_store.dart';
import '../../../services/chat_service.dart';
import '../../../services/user_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../subscription/creator_upsell.dart';

enum _FolderPickTab { all, chats, channels }

/// Создание или редактирование папки чатов (Telegram-style).
class ChatFolderEditScreen extends StatefulWidget {
  const ChatFolderEditScreen({
    super.key,
    this.folder,
    this.initialConversationIds = const [],
    this.initialChannelIds = const [],
  });

  final ChatFolder? folder;
  final List<int> initialConversationIds;
  final List<int> initialChannelIds;

  @override
  State<ChatFolderEditScreen> createState() => _ChatFolderEditScreenState();
}

class _FolderPickItem {
  _FolderPickItem({
    required this.key,
    required this.title,
    required this.subtitle,
    this.conversationId,
    this.channelId,
  });

  final String key;
  final String title;
  final String subtitle;
  final int? conversationId;
  final int? channelId;

  bool get isChat => conversationId != null;
  bool get isChannel => channelId != null;
}

class _ChatFolderEditScreenState extends State<ChatFolderEditScreen> {
  static const _channelListLimit = 50;

  final _nameController = TextEditingController();
  final _iconController = TextEditingController();
  final _searchController = TextEditingController();
  final _selectedConv = <int>{};
  final _selectedCh = <int>{};
  ChatFolderFilters _filters = const ChatFolderFilters();
  List<_FolderPickItem> _items = [];
  bool _loadingPickList = true;
  bool _saving = false;
  Object? _chatsLoadError;
  Object? _channelsLoadError;
  _FolderPickTab _tab = _FolderPickTab.all;
  String _searchQuery = '';
  bool _openOnLaunch = false;

  bool get _isEdit => widget.folder != null;

  @override
  void initState() {
    super.initState();
    final folder = widget.folder;
    if (folder != null) {
      _nameController.text = folder.name;
      if (folder.icon != null) _iconController.text = folder.icon!;
      _selectedConv.addAll(folder.conversationIds);
      _selectedCh.addAll(folder.channelIds);
      _filters = folder.filters;
      _openOnLaunch =
          AuthService.instance.currentUser?.defaultFolderId == folder.id;
    } else {
      _selectedConv.addAll(widget.initialConversationIds);
      _selectedCh.addAll(widget.initialChannelIds);
    }
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    unawaited(_loadPickList());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPickList() async {
    setState(() {
      _loadingPickList = true;
      _chatsLoadError = null;
      _channelsLoadError = null;
    });

    final chatItems = <_FolderPickItem>[];
    final channelItems = <_FolderPickItem>[];

    await Future.wait<void>([
      () async {
        try {
          final chats = await ChatService.listConversations();
          for (final c in chats) {
            if (c.isSaved) continue;
            chatItems.add(
              _FolderPickItem(
                key: 'c_${c.id}',
                title: c.displayTitle,
                subtitle: c.isGroup ? 'Группа' : 'Личный чат',
                conversationId: c.id,
              ),
            );
          }
        } catch (e) {
          _chatsLoadError = e;
        }
      }(),
      () async {
        try {
          final owned = await ChannelService.listChannels(
            limit: _channelListLimit,
            offset: 0,
            mine: true,
            withLastPost: false,
          );
          final subscribed = await ChannelService.listChannels(
            limit: _channelListLimit,
            offset: 0,
            subscribed: true,
            withLastPost: false,
          );
          final seen = <int>{};
          for (final ch in [...owned.items, ...subscribed.items]) {
            if (!seen.add(ch.id)) continue;
            channelItems.add(
              _FolderPickItem(
                key: 'ch_${ch.id}',
                title: ch.name,
                subtitle: 'Канал',
                channelId: ch.id,
              ),
            );
          }
        } catch (e) {
          _channelsLoadError = e;
        }
      }(),
    ]);

    final items = [...chatItems, ...channelItems]
      ..sort((a, b) => a.title.compareTo(b.title));

    if (!mounted) return;
    setState(() {
      _items = items;
      _loadingPickList = false;
    });
  }

  List<_FolderPickItem> get _visibleItems {
    var list = _items;
    switch (_tab) {
      case _FolderPickTab.chats:
        list = list.where((i) => i.isChat).toList();
      case _FolderPickTab.channels:
        list = list.where((i) => i.isChannel).toList();
      case _FolderPickTab.all:
        break;
    }
    if (_searchQuery.isEmpty) return list;
    return list
        .where((i) => i.title.toLowerCase().contains(_searchQuery))
        .toList();
  }

  bool _isSelected(_FolderPickItem item) {
    if (item.conversationId != null) {
      return _selectedConv.contains(item.conversationId);
    }
    return _selectedCh.contains(item.channelId);
  }

  void _toggle(_FolderPickItem item) {
    setState(() {
      if (item.conversationId != null) {
        final id = item.conversationId!;
        if (_selectedConv.contains(id)) {
          _selectedConv.remove(id);
        } else {
          _selectedConv.add(id);
        }
      } else if (item.channelId != null) {
        final id = item.channelId!;
        if (_selectedCh.contains(id)) {
          _selectedCh.remove(id);
        } else {
          _selectedCh.add(id);
        }
      }
    });
  }

  int get _selectedCount => _selectedConv.length + _selectedCh.length;

  bool _allowFolderFilters({required bool enabling}) {
    if (!enabling || hasFlexFeature('folder_filters')) return true;
    showCreatorUpsell(context);
    return false;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название папки')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final icon = _iconController.text.trim();
      if (icon.isNotEmpty && !hasFlexFeature('folder_icons')) {
        await showCreatorUpsell(context);
        return;
      }
      if (_filters.needsFolderFiltersPlus && !hasFlexFeature('folder_filters')) {
        await showCreatorUpsell(context);
        return;
      }
      final conv = _selectedConv.toList();
      final ch = _selectedCh.toList();
      ChatFolder result;
      if (_isEdit) {
        result = await ChatFolderStore.updateFolder(
          widget.folder!.copyWith(
            name: name,
            icon: icon.isEmpty ? null : icon,
            conversationIds: conv,
            channelIds: ch,
            filters: _filters,
          ),
        );
      } else {
        result = await ChatFolderStore.createFolder(
          name: name,
          icon: icon.isEmpty ? null : icon,
          conversationIds: conv,
          channelIds: ch,
          filters: _filters,
        );
      }
      if (_openOnLaunch) {
        final updated = await UserService.updateProfile(
          defaultFolderId: result.id,
        );
        await AuthService.persistUpdatedUser(updated);
      } else if (_isEdit &&
          AuthService.instance.currentUser?.defaultFolderId == result.id) {
        final updated = await UserService.updateProfile(defaultFolderId: 0);
        await AuthService.persistUpdatedUser(updated);
      }
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteFolder() async {
    final folder = widget.folder;
    if (folder == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          'Папка «${folder.name}» будет удалена. Чаты и каналы останутся в «Все чаты».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ChatFolderStore.deleteFolder(folder.id);
    if (!mounted) return;
    Navigator.pop(context, 'deleted');
  }

  Widget _buildLoadBanner() {
    if (_chatsLoadError == null && _channelsLoadError == null) {
      return const SizedBox.shrink();
    }
    final parts = <String>[];
    if (_chatsLoadError != null) parts.add('чаты');
    if (_channelsLoadError != null) parts.add('каналы');
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      content: Text(
        'Не удалось загрузить ${parts.join(' и ')}. '
        'Можно сохранить папку с фильтрами или повторить.',
      ),
      leading: const Icon(Icons.info_outline),
      actions: [
        TextButton(onPressed: _loadPickList, child: const Text('Повторить')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Папка' : 'Новая папка'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Удалить папку',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _deleteFolder,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLoadBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название папки',
                    hintText: 'Работа, Семья, Новости…',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: !_isEdit,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _iconController,
                  readOnly: !hasFlexFeature('folder_icons'),
                  onTap: hasFlexFeature('folder_icons')
                      ? null
                      : () => showCreatorUpsell(context),
                  decoration: InputDecoration(
                    labelText: 'Эмодзи (необязательно)',
                    hintText: '📁',
                    suffixIcon: hasFlexFeature('folder_icons')
                        ? null
                        : const Icon(Icons.lock_outline),
                  ),
                  maxLength: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Открывать при запуске'),
                  subtitle: Text(
                    hasFlexFeature('any_emoji_reactions')
                        ? 'Эта папка откроется вместо последней выбранной'
                        : 'Доступно с уровня 37',
                  ),
                  value: _openOnLaunch,
                  secondary: hasFlexFeature('any_emoji_reactions')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (v && !hasFlexFeature('any_emoji_reactions')) {
                      showCreatorUpsell(context);
                      return;
                    }
                    setState(() => _openOnLaunch = v);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Кого включить автоматически',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Как в Telegram: можно не выбирать чаты вручную — '
                  'папка соберётся по правилам ниже.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Групповые чаты'),
                  value: _filters.groups,
                  onChanged: (v) =>
                      setState(() => _filters = _filters.copyWith(groups: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Личные чаты'),
                  subtitle: const Text('Все диалоги один-на-один'),
                  value: _filters.direct,
                  onChanged: (v) =>
                      setState(() => _filters = _filters.copyWith(direct: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Контакты'),
                  subtitle: Text(
                    hasFlexFeature('folder_filters')
                        ? 'Личные чаты с людьми из контактов'
                        : 'Доступно с уровня 31',
                  ),
                  value: _filters.contacts,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(
                      () => _filters = _filters.copyWith(contacts: v),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Не контакты'),
                  subtitle: Text(
                    hasFlexFeature('folder_filters')
                        ? 'Личные чаты с людьми вне контактов'
                        : 'Доступно с уровня 31',
                  ),
                  value: _filters.nonContacts,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(
                      () => _filters = _filters.copyWith(nonContacts: v),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Боты'),
                  subtitle: Text(
                    hasFlexFeature('folder_filters')
                        ? 'Личные чаты с ботами'
                        : 'Доступно с уровня 31',
                  ),
                  value: _filters.bots,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(() {
                      _filters = _filters.copyWith(
                        bots: v,
                        excludeBots: v ? false : _filters.excludeBots,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Каналы'),
                  value: _filters.channels,
                  onChanged: (v) => setState(
                    () => _filters = _filters.copyWith(channels: v),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Только непрочитанные'),
                  subtitle: hasFlexFeature('folder_filters')
                      ? null
                      : const Text('Доступно с уровня 31'),
                  value: _filters.unreadOnly,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(
                      () => _filters = _filters.copyWith(unreadOnly: v),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Без чатов без звука'),
                  subtitle: hasFlexFeature('folder_filters')
                      ? null
                      : const Text('Доступно с уровня 31'),
                  value: _filters.excludeMuted,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(
                      () => _filters = _filters.copyWith(excludeMuted: v),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Без архивных'),
                  subtitle: hasFlexFeature('folder_filters')
                      ? null
                      : const Text('Доступно с уровня 31'),
                  value: _filters.excludeArchived,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(
                      () => _filters = _filters.copyWith(excludeArchived: v),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Без ботов'),
                  subtitle: Text(
                    hasFlexFeature('folder_filters')
                        ? 'Скрыть личные чаты с ботами'
                        : 'Доступно с уровня 31',
                  ),
                  value: _filters.excludeBots,
                  secondary: hasFlexFeature('folder_filters')
                      ? null
                      : const Icon(Icons.lock_outline),
                  onChanged: (v) {
                    if (!_allowFolderFilters(enabling: v)) return;
                    setState(() {
                      _filters = _filters.copyWith(
                        excludeBots: v,
                        bots: v ? false : _filters.bots,
                      );
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Исключения и добавления',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (_selectedCount > 0)
                      Text(
                        '$_selectedCount',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск чатов и каналов',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<_FolderPickTab>(
                  segments: const [
                    ButtonSegment(
                      value: _FolderPickTab.all,
                      label: Text('Все'),
                    ),
                    ButtonSegment(
                      value: _FolderPickTab.chats,
                      label: Text('Чаты'),
                    ),
                    ButtonSegment(
                      value: _FolderPickTab.channels,
                      label: Text('Каналы'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) =>
                      setState(() => _tab = s.first),
                ),
                const SizedBox(height: 8),
                if (_loadingPickList)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'Ничего не найдено'
                          : 'Нет чатов для добавления. Используйте фильтры выше.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  ...visible.map(
                    (item) => CheckboxListTile(
                      value: _isSelected(item),
                      onChanged: (_) => _toggle(item),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
