import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_sheet_prefs.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import '../application/chat_inbox_optimistic.dart';
import '../application/chat_thread_prefetch.dart';
import '../../../services/chat_thread_ui_prefs.dart';
import '../../../services/user_realtime_service.dart';
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
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;
  Timer? _typingTicker;
  final Map<int, Map<int, DateTime>> _typingUntilByUser = {};
  final Map<int, Map<int, String>> _typingActivityByUser = {};

  static String _chatKey(int id) => 'chat_$id';
  static String _channelKey(int id) => 'channel_$id';

  @override
  void initState() {
    super.initState();
    _realtimeSub = UserRealtimeService.instance.events.listen(_onRealtime);
    _load();
  }

  void _onRealtime(UserRealtimeEvent event) {
    if (!mounted) return;
    if (event.event == 'chat.typing') {
      final cid = event.conversationId;
      if (cid == null) return;
      if (!_chats.any((c) => c.id == cid)) return;
      final uid = event.userId ?? 0;
      final activity =
          event.activity == 'recording' ? 'recording' : 'typing';
      setState(() {
        final byUser = _typingUntilByUser.putIfAbsent(cid, () => {});
        byUser[uid] = DateTime.now().add(const Duration(seconds: 5));
        final byActivity = _typingActivityByUser.putIfAbsent(cid, () => {});
        byActivity[uid] = activity;
      });
      _ensureTypingTicker();
      return;
    }
    if (event.event == 'user.presence') {
      final uid = event.userId;
      final seen = event.lastSeenAt;
      if (uid == null || seen == null) return;
      var changed = false;
      for (var i = 0; i < _chats.length; i++) {
        final peer = _chats[i].peer;
        if (peer == null || peer.id != uid) continue;
        _chats[i] = _chats[i].copyWith(
          peer: peer.copyWith(lastSeenAt: seen),
        );
        changed = true;
      }
      if (changed) setState(() {});
    }
  }

  void _ensureTypingTicker() {
    if (_typingTicker != null) return;
    _typingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final hasAny = _typingUntilByUser.isNotEmpty;
      var needsUpdate = false;
      for (final byUser in _typingUntilByUser.values) {
        if (byUser.values.any((until) => !until.isAfter(now))) {
          needsUpdate = true;
          break;
        }
      }
      if (!needsUpdate) {
        if (!hasAny) {
          _typingTicker?.cancel();
          _typingTicker = null;
        }
        return;
      }
      setState(() {
        final emptyConvs = <int>[];
        for (final entry in _typingUntilByUser.entries) {
          final expired = <int>[];
          entry.value.removeWhere((uid, until) {
            final gone = !until.isAfter(now);
            if (gone) expired.add(uid);
            return gone;
          });
          final activities = _typingActivityByUser[entry.key];
          if (activities != null) {
            for (final uid in expired) {
              activities.remove(uid);
            }
            if (activities.isEmpty) {
              _typingActivityByUser.remove(entry.key);
            }
          }
          if (entry.value.isEmpty) emptyConvs.add(entry.key);
        }
        for (final id in emptyConvs) {
          _typingUntilByUser.remove(id);
          _typingActivityByUser.remove(id);
        }
      });
      if (_typingUntilByUser.isEmpty) {
        _typingTicker?.cancel();
        _typingTicker = null;
      }
    });
  }

  String? _typingLabelFor(int conversationId) {
    final byUser = _typingUntilByUser[conversationId];
    if (byUser == null || byUser.isEmpty) return null;
    final now = DateTime.now();
    final active = byUser.entries
        .where((e) => e.value.isAfter(now))
        .map((e) => e.key)
        .toList();
    if (active.isEmpty) return null;
    final activities = _typingActivityByUser[conversationId] ?? const {};
    final recording = active.any((id) => activities[id] == 'recording');
    ChatConversation? chat;
    for (final c in _chats) {
      if (c.id == conversationId) {
        chat = c;
        break;
      }
    }
    if (chat == null || !chat.isGroup) {
      return recording ? 'записывает голосовое…' : 'печатает…';
    }
    final names = <String>[];
    for (final id in active) {
      final peer = chat.peer;
      if (peer != null && peer.id == id) {
        names.add(peer.displayName.split(' ').first);
        continue;
      }
      for (final m in chat.membersPreview) {
        if (m.id == id) {
          names.add(m.displayName.split(' ').first);
          break;
        }
      }
    }
    if (recording) {
      if (names.isEmpty) {
        return active.length > 1
            ? 'записывают голосовое…'
            : 'записывает голосовое…';
      }
      if (names.length == 1) return '${names.first} записывает голосовое…';
      return '${names.length} записывают голосовое…';
    }
    if (names.isEmpty) {
      return active.length > 1 ? 'печатают…' : 'печатает…';
    }
    if (names.length == 1) return '${names.first} печатает…';
    if (names.length == 2) {
      return '${names[0]} и ${names[1]} печатают…';
    }
    return '${names.length} печатают…';
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _typingTicker?.cancel();
    super.dispose();
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
      var chatItems = results[0] as List<ChatConversation>;
      final archivedIds = results[1] as Set<int>;
      final expired = await _expireTimedMutes(chatItems);
      if (expired > 0) {
        chatItems = await ChatService.listConversations(archived: true);
      }
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

  Future<int> _expireTimedMutes(List<ChatConversation> chats) async {
    var changed = 0;
    final now = DateTime.now();
    for (final chat in chats) {
      if (!chat.muted) continue;
      final until = chat.mutedUntil?.toLocal() ??
          await ChatThreadUiPrefs.getMuteUntil(chat.id);
      if (until == null || until.isAfter(now)) {
        if (until != null) {
          await ChatThreadUiPrefs.setMuteUntil(chat.id, until);
        }
        continue;
      }
      try {
        await ChatService.setMuted(conversationId: chat.id, muted: false);
        await ChatThreadUiPrefs.setMuteUntil(chat.id, null);
        changed++;
      } catch (_) {}
    }
    return changed;
  }

  Future<void> _unarchiveChat(ChatConversation chat) async {
    setState(() => _chats.removeWhere((c) => c.id == chat.id));
    unawaited(
      ChatCacheService.upsertConversation(
        ChatInboxOptimistic.applyArchive(chat, archived: false),
      ),
    );
    try {
      await ChatService.setArchived(
        conversationId: chat.id,
        archived: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _chats.add(chat));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _unarchiveChannel(Channel channel) async {
    setState(() => _channels.removeWhere((c) => c.id == channel.id));
    try {
      await ChannelSheetPrefs.setArchived(channel.id, false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _channels.add(channel));
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
                                  typingLabel: _typingLabelFor(chat.id),
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
    this.typingLabel,
  });

  final ChatConversation chat;
  final VoidCallback onUnarchive;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onLongPress;
  final String? typingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = chat.lastMessage;
    final hasUnread = chat.unreadCount > 0 ||
        chat.unreadMentionsCount > 0 ||
        chat.unreadReactionsCount > 0;
    final hasTyping = (typingLabel?.trim().isNotEmpty ?? false);
    final preview = hasTyping
        ? typingLabel!.trim()
        : chatHubBodyPreview(last, isSaved: chat.isSaved);
    final prefix = hasTyping
        ? null
        : (last == null
            ? null
            : (last.isMine
                ? 'Вы: '
                : (chat.isGroup && (last.senderName?.isNotEmpty ?? false)
                    ? '${last.senderName}: '
                    : null)));
    final peer = chat.peer;

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
                : (peer != null && !chat.isGroup && !chat.isSaved
                    ? ChatHubUserAvatar(user: peer)
                    : Icon(
                        chat.isSaved
                            ? Icons.bookmark_rounded
                            : chat.isGroup
                                ? Icons.groups_rounded
                                : Icons.person_rounded,
                      )),
            title: Text(
              chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            subtitle: hasTyping
                ? Row(
                    children: [
                      Flexible(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TelegramTypingDots(
                        color: scheme.primary,
                        size: 3.0,
                      ),
                    ],
                  )
                : Text(
                    prefix == null ? preview : '$prefix$preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
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
                        : (chat.unreadMentionsCount > 0
                            ? chat.unreadMentionsCount
                            : chat.unreadReactionsCount),
                    muted: chat.muted,
                    hasMention: chat.unreadMentionsCount > 0,
                    hasReaction: chat.unreadMentionsCount <= 0 &&
                        chat.unreadReactionsCount > 0,
                  ),
                ],
              ],
            ),
            onTap: () async {
              if (selectionMode) {
                onToggleSelect();
                return;
              }
              unawaited(ChatThreadPrefetch.warm(chat.id));
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
