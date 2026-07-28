import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_sheet_prefs.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/telegram_ui.dart';
import 'widgets/chats_hub_tiles.dart';

class ChatArchivedScreen extends StatefulWidget {
  const ChatArchivedScreen({super.key});

  @override
  State<ChatArchivedScreen> createState() => _ChatArchivedScreenState();
}

class _ChatArchivedScreenState extends State<ChatArchivedScreen> {
  List<ChatConversation> _chats = [];
  List<Channel> _channels = [];
  bool _loading = true;
  Object? _error;
  bool _selectionMode = false;
  final Set<String> _selectedKeys = {};
  bool _bulkBusy = false;

  static String _chatKey(int id) => 'chat_$id';
  static String _channelKey(int id) => 'channel_$id';

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
      await ChannelSheetPrefs.syncFromServer(force: true);
      final results = await Future.wait<Object>([
        ChatService.listConversations(archived: true),
        ChannelSheetPrefs.listArchivedIds(),
      ]);
      final chatItems = results[0] as List<ChatConversation>;
      final archivedIds = results[1] as Set<int>;
      final channels = <Channel>[];
      for (final id in archivedIds) {
        try {
          final detail = await ChannelService.getChannel(id);
          channels.add(detail);
        } catch (_) {}
      }
      channels.sort(
        (a, b) => (b.lastPostAt ?? b.createdAt)
            .compareTo(a.lastPostAt ?? a.createdAt),
      );
      if (!mounted) return;
      setState(() {
        _chats = chatItems;
        _channels = channels;
        _loading = false;
        final valid = <String>{
          ...chatItems.map((c) => _chatKey(c.id)),
          ...channels.map((c) => _channelKey(c.id)),
        };
        _selectedKeys.removeWhere((k) => !valid.contains(k));
        if (_selectedKeys.isEmpty) _selectionMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _enterSelection([String? key]) {
    setState(() {
      _selectionMode = true;
      _selectedKeys.clear();
      if (key != null) _selectedKeys.add(key);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedKeys.clear();
    });
  }

  void _toggleSelected(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        if (_selectedKeys.isEmpty) _selectionMode = false;
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectionMode = true;
      _selectedKeys
        ..clear()
        ..addAll(_chats.map((c) => _chatKey(c.id)))
        ..addAll(_channels.map((c) => _channelKey(c.id)));
    });
  }

  Future<void> _unarchiveChat(ChatConversation chat) async {
    try {
      await ChatService.setArchived(
        conversationId: chat.id,
        archived: false,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _unarchiveChannel(Channel channel) async {
    try {
      await ChannelSheetPrefs.setArchived(channel.id, false);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _unarchiveSelected() async {
    if (_selectedKeys.isEmpty || _bulkBusy) return;
    setState(() => _bulkBusy = true);
    var ok = 0;
    var fail = 0;
    try {
      for (final chat in _chats) {
        final key = _chatKey(chat.id);
        if (!_selectedKeys.contains(key)) continue;
        try {
          await ChatService.setArchived(
            conversationId: chat.id,
            archived: false,
          );
          ok += 1;
        } catch (_) {
          fail += 1;
        }
      }
      for (final channel in _channels) {
        final key = _channelKey(channel.id);
        if (!_selectedKeys.contains(key)) continue;
        try {
          await ChannelSheetPrefs.setArchived(channel.id, false);
          ok += 1;
        } catch (_) {
          fail += 1;
        }
      }
      if (!mounted) return;
      _exitSelection();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fail == 0
                ? 'Разархивировано: $ok'
                : 'Разархивировано: $ok, ошибок: $fail',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _unarchiveAll() async {
    if (_chats.isEmpty && _channels.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Разархивировать все?'),
        content: Text(
          'Вернуть в основной список ${_chats.length + _channels.length} '
          '${_chats.length + _channels.length == 1 ? 'чат' : 'чатов'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Разархивировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _selectAll();
    await _unarchiveSelected();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _chats.isEmpty && _channels.isEmpty;
    final totalCount = _chats.length + _channels.length;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelection();
      },
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _bulkBusy ? null : _exitSelection,
                ),
                title: Text('${_selectedKeys.length}'),
                actions: [
                  if (_selectedKeys.length < totalCount)
                    IconButton(
                      tooltip: 'Выбрать все',
                      onPressed: _bulkBusy ? null : _selectAll,
                      icon: const Icon(Icons.select_all),
                    ),
                  IconButton(
                    tooltip: 'Разархивировать',
                    onPressed: _bulkBusy || _selectedKeys.isEmpty
                        ? null
                        : _unarchiveSelected,
                    icon: _bulkBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.unarchive_outlined),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Архив'),
                actions: [
                  if (!isEmpty && !_loading)
                    IconButton(
                      tooltip: 'Выбрать',
                      onPressed: () => _enterSelection(),
                      icon: const Icon(Icons.checklist_rtl),
                    ),
                  if (!isEmpty && !_loading)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'unarchive_all') {
                          _unarchiveAll();
                        } else if (v == 'select') {
                          _enterSelection();
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'select',
                          child: Text('Выбрать'),
                        ),
                        PopupMenuItem(
                          value: 'unarchive_all',
                          child: Text('Разархивировать все'),
                        ),
                      ],
                    ),
                ],
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? AppEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Ошибка',
                    subtitle: userVisibleError(_error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  )
                : isEmpty
                    ? const AppEmptyState(
                        icon: Icons.archive_outlined,
                        title: 'Архив пуст',
                        subtitle:
                            'Свайпните чат или канал влево в списке «Чаты», '
                            'или удержите строку и выберите «В архив».',
                      )
                    : RefreshIndicator(
                        onRefresh: _selectionMode ? () async {} : _load,
                        child: ListView(
                          children: [
                            if (_chats.isNotEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  'Чаты',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              ..._chats.map((chat) {
                                final key = _chatKey(chat.id);
                                return _ArchivedChatTile(
                                  chat: chat,
                                  selectionMode: _selectionMode,
                                  selected: _selectedKeys.contains(key),
                                  onUnarchive: () => _unarchiveChat(chat),
                                  onToggleSelect: () => _toggleSelected(key),
                                  onLongPress: () {
                                    if (_selectionMode) {
                                      _toggleSelected(key);
                                    } else {
                                      _enterSelection(key);
                                    }
                                  },
                                );
                              }),
                            ],
                            if (_channels.isNotEmpty) ...[
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  _chats.isEmpty ? 12 : 20,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  'Каналы',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              ..._channels.map((channel) {
                                final key = _channelKey(channel.id);
                                return _ArchivedChannelTile(
                                  channel: channel,
                                  selectionMode: _selectionMode,
                                  selected: _selectedKeys.contains(key),
                                  onUnarchive: () =>
                                      _unarchiveChannel(channel),
                                  onToggleSelect: () => _toggleSelected(key),
                                  onLongPress: () {
                                    if (_selectionMode) {
                                      _toggleSelected(key);
                                    } else {
                                      _enterSelection(key);
                                    }
                                  },
                                  onOpen: () async {
                                    await context.push(
                                      ChannelDetailRoute.pathFor(channel.id),
                                    );
                                    if (mounted) _load();
                                  },
                                );
                              }),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class _ArchivedChatTile extends StatelessWidget {
  const _ArchivedChatTile({
    required this.chat,
    required this.onUnarchive,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onLongPress,
  });

  final ChatConversation chat;
  final VoidCallback onUnarchive;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = chat.lastMessage;
    final hasUnread =
        chat.unreadCount > 0 || chat.unreadMentionsCount > 0;
    final preview = chatHubBodyPreview(last, isSaved: chat.isSaved);
    final prefix = last == null
        ? null
        : (last.isMine
            ? 'Вы: '
            : (chat.isGroup && (last.senderName?.isNotEmpty ?? false)
                ? '${last.senderName}: '
                : null));

    final tile = Material(
      color: hasUnread
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      child: Column(
        children: [
          ListTile(
            leading: selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect(),
                  )
                : Icon(
                    chat.isSaved
                        ? Icons.bookmark_rounded
                        : chat.isGroup
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                  ),
            title: Text(
              chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              prefix == null ? preview : '$prefix$preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chatHubFormatInboxTime(
                    last?.createdAt ?? chat.updatedAt,
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  TelegramUnreadBadge(
                    count: chat.unreadCount > 0
                        ? chat.unreadCount
                        : chat.unreadMentionsCount,
                    muted: chat.muted,
                    hasMention: chat.unreadMentionsCount > 0,
                  ),
                ],
              ],
            ),
            onTap: () async {
              if (selectionMode) {
                onToggleSelect();
                return;
              }
              await context.push(
                ChatThreadRoute.pathFor(chat),
                extra: chat,
              );
            },
            onLongPress: onLongPress,
          ),
          const Divider(height: 1, indent: 72),
        ],
      ),
    );

    if (selectionMode) return tile;

    return Dismissible(
      key: ValueKey('archived_chat_${chat.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.primary,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.unarchive_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      confirmDismiss: (_) async {
        onUnarchive();
        return false;
      },
      child: tile,
    );
  }
}

class _ArchivedChannelTile extends StatelessWidget {
  const _ArchivedChannelTile({
    required this.channel,
    required this.onUnarchive,
    required this.onOpen,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onLongPress,
  });

  final Channel channel;
  final VoidCallback onUnarchive;
  final VoidCallback onOpen;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = channel.inboxUnreadPosts;
    final hasUnread = unread > 0;
    final preview = (channel.lastPostPreview?.trim().isNotEmpty ?? false)
        ? channel.lastPostPreview!.trim()
        : ((channel.description?.trim().isNotEmpty ?? false)
            ? channel.description!.trim()
            : 'Канал');

    final tile = Material(
      color: hasUnread
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      child: Column(
        children: [
          ListTile(
            leading: selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect(),
                  )
                : const Icon(Icons.campaign_outlined),
            title: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chatHubFormatInboxTime(
                    channel.lastPostAt ?? channel.createdAt,
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  TelegramUnreadBadge(count: unread),
                ],
              ],
            ),
            onTap: () {
              if (selectionMode) {
                onToggleSelect();
                return;
              }
              onOpen();
            },
            onLongPress: onLongPress,
          ),
          const Divider(height: 1, indent: 72),
        ],
      ),
    );

    if (selectionMode) return tile;

    return Dismissible(
      key: ValueKey('archived_channel_${channel.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.primary,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.unarchive_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      confirmDismiss: (_) async {
        onUnarchive();
        return false;
      },
      child: tile,
    );
  }
}
