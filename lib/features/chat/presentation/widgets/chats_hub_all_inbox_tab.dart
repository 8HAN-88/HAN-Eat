import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_router.dart';
import '../../../../core/layout/floating_bottom_padding.dart';
import '../../../../core/network/feed_load_helper.dart';
import '../../../../models/chat_models.dart';
import '../../../../services/api_reachability_service.dart';
import '../../../../services/channel_service.dart';
import '../../../../services/channel_sheet_prefs.dart';
import '../../../../services/chat_cache_service.dart';
import '../../../../services/chat_folder_store.dart';
import '../../../../services/chat_hub_ui_prefs.dart';
import '../../../../services/chat_service.dart';
import '../../../../services/user_realtime_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_empty_state.dart';
import '../../../../widgets/chat_inbox_skeleton.dart';
import '../../../channels/application/channels_list_refresh_provider.dart';
import '../../../navigation/application/shell_chat_badge_refresh_provider.dart';
import '../../../navigation/application/shell_tab_visibility.dart';
import '../../application/chat_realtime_signals.dart';
import '../../application/chats_hub_refresh_provider.dart';
import '../../widgets/inbox_slidable_tile.dart';
import '../chat_folder_edit_screen.dart';
import '../chat_folders_manage_sheet.dart';
import 'chats_hub_folder_bar.dart';
import 'chats_hub_gestures_hint.dart';
import 'chats_hub_tiles.dart';
import 'inbox_hub_entries.dart';

class ChatsHubAllInboxTab extends ConsumerStatefulWidget {
  const ChatsHubAllInboxTab({
    super.key,
    this.searchQuery = '',
    required this.onSwitchToContacts,
  });

  final String searchQuery;
  final VoidCallback onSwitchToContacts;

  @override
  ConsumerState<ChatsHubAllInboxTab> createState() => _ChatsHubAllInboxTabState();
}

class _ChatsHubAllInboxTabState extends ConsumerState<ChatsHubAllInboxTab>
    with WidgetsBindingObserver {
  final _entries = <InboxHubEntry>[];
  List<Channel> _recommended = [];
  bool _loading = false;
  bool _started = false;
  Object? _error;
  Object? _chatsPartialError;
  int _loadSeq = 0;
  int? _hubActionChatId;
  Timer? _pollTimer;
  StreamSubscription<void>? _signalSub;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;
  VoidCallback? _apiReachabilityListener;
  VoidCallback? _realtimeConnectedListener;
  bool _appPaused = false;
  List<ChatFolder> _folders = [];
  int? _selectedFolderId;
  bool _showGesturesHint = false;
  bool _servingFromCache = false;

  void _selectFolder(int? folderId) {
    setState(() => _selectedFolderId = folderId);
    unawaited(ChatHubUiPrefs.saveSelectedFolderId(folderId));
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await ChatFolderStore.listFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        if (_selectedFolderId != null &&
            !folders.any((f) => f.id == _selectedFolderId)) {
          _selectedFolderId = null;
          unawaited(ChatHubUiPrefs.saveSelectedFolderId(null));
        }
      });
    } catch (_) {}
  }

  Future<void> _restoreHubUiPrefs() async {
    final results = await Future.wait([
      ChatHubUiPrefs.loadSelectedFolderId(),
      ChatHubUiPrefs.isGesturesHintDismissed(),
    ]);
    if (!mounted) return;
    setState(() {
      _selectedFolderId = results[0] as int?;
      _showGesturesHint = !(results[1] as bool);
    });
  }

  Future<void> _dismissGesturesHint() async {
    await ChatHubUiPrefs.dismissGesturesHint();
    if (mounted) setState(() => _showGesturesHint = false);
  }

  Future<void> _openCreateFolder({
    List<int> conversationIds = const [],
    List<int> channelIds = const [],
  }) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ChatFolderEditScreen(
          initialConversationIds: conversationIds,
          initialChannelIds: channelIds,
        ),
      ),
    );
    if (!mounted) return;
    await _loadFolders();
    if (result is ChatFolder) {
      _selectFolder(result.id);
    }
  }

  Future<void> _openEditFolder(ChatFolder folder) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ChatFolderEditScreen(folder: folder),
      ),
    );
    if (!mounted) return;
    await _loadFolders();
    if (result == 'deleted' && _selectedFolderId == folder.id) {
      _selectFolder(null);
    }
  }

  Future<void> _showAddToFolderSheet({
    int? conversationId,
    int? channelId,
  }) async {
    await _loadFolders();
    if (!mounted) return;
    if (_folders.isEmpty) {
      await _openCreateFolder(
        conversationIds:
            conversationId != null ? [conversationId] : const [],
        channelIds: channelId != null ? [channelId] : const [],
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Новая папка'),
              onTap: () {
                Navigator.pop(ctx);
                _openCreateFolder(
                  conversationIds:
                      conversationId != null ? [conversationId] : const [],
                  channelIds: channelId != null ? [channelId] : const [],
                );
              },
            ),
            const Divider(height: 1),
            ..._folders.map((folder) {
              final inFolder = conversationId != null
                  ? folder.containsConversation(conversationId)
                  : channelId != null && folder.containsChannel(channelId);
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.displayLabel),
                trailing: inFolder
                    ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    if (inFolder) {
                      await ChatFolderStore.removeFromFolder(
                        folderId: folder.id,
                        conversationId: conversationId,
                        channelId: channelId,
                      );
                    } else {
                      await ChatFolderStore.addToFolder(
                        folderId: folder.id,
                        conversationId: conversationId,
                        channelId: channelId,
                      );
                    }
                    if (!mounted) return;
                    await _loadFolders();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          inFolder
                              ? 'Убрано из «${folder.name}»'
                              : 'Добавлено в «${folder.name}»',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(userVisibleError(e))),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  ChatFolder? get _activeFolder {
    if (_selectedFolderId == null) return null;
    for (final f in _folders) {
      if (f.id == _selectedFolderId) return f;
    }
    return null;
  }

  Future<void> _openManageFolders() async {
    if (_folders.isEmpty) return;
    final result = await showModalBottomSheet<List<ChatFolder>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChatFoldersManageSheet(folders: _folders),
    );
    if (!mounted || result == null) return;
    setState(() => _folders = result);
  }

  bool _entryMatchesFolder(InboxHubEntry entry, ChatFolder folder) {
    if (entry is ChatInboxEntry) {
      final chat = entry.chat;
      if (chat.isSaved) return false;
      if (folder.containsConversation(chat.id)) return true;
      if (folder.filters.groups && chat.isGroup) return true;
      if (folder.filters.unreadOnly && chat.unreadCount > 0) return true;
      return false;
    }
    if (entry is ChannelInboxEntry) {
      if (folder.containsChannel(entry.channel.id)) return true;
      if (folder.filters.channels) return true;
      if (folder.filters.unreadOnly && entry.channel.inboxUnreadPosts > 0) {
        return true;
      }
      return false;
    }
    return false;
  }

  ChatConversation? _savedChat;
  bool _openingSaved = false;

  bool get _showSavedPinned =>
      widget.searchQuery.trim().isEmpty && _selectedFolderId == null;

  ChatConversation get _savedChatTile => _savedChat ??
      ChatConversation(
        id: 0,
        type: 'saved',
        updatedAt: DateTime.now(),
      );

  void _hydrateFromCache() {
    final cached = ChatCacheService.peekConversations();
    if (cached == null || cached.isEmpty) return;
    final cachedSaved = _extractSavedChat(cached);
    final cachedRest = _withoutSavedChat(cached, cachedSaved);
    if (cachedSaved != null) _savedChat = cachedSaved;
    _entries
      ..clear()
      ..addAll(cachedRest.map(ChatInboxEntry.new));
    _servingFromCache = true;
    _loading = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateFromCache();
    ShellTabVisibility.activeIndex.addListener(_onShellTabChanged);
    _signalSub = ChatRealtimeSignals.instance.hubRefresh.listen((_) {
      if (mounted && _started && ShellTabVisibility.chatsActive && !_loading) {
        _load(silent: true);
      }
    });
    _realtimeSub = UserRealtimeService.instance.events.listen((event) {
      if (!mounted || !_started || !ShellTabVisibility.chatsActive || _loading) {
        return;
      }
      if (event.event == 'chat.inbox' ||
          event.event == 'sync' ||
          (event.event == 'notification.new' &&
              event.notificationType == 'message')) {
        _load(silent: true);
      }
    });
    _realtimeConnectedListener = () {
      if (!mounted) return;
      _resetPollTimer();
      if (_started && ShellTabVisibility.chatsActive && !_loading) {
        _load(silent: true);
      }
    };
    UserRealtimeService.instance.connected
        .addListener(_realtimeConnectedListener!);
    _apiReachabilityListener = () {
      if (!ApiReachabilityService.instance.isApiReachable.value) return;
      if (mounted && _started && ShellTabVisibility.chatsActive && !_loading) {
        _load(silent: true);
      }
    };
    ApiReachabilityService.instance.isApiReachable
        .addListener(_apiReachabilityListener!);
    unawaited(_restoreHubUiPrefs());
    unawaited(_loadFolders());
    _maybeStartLoading();
  }

  void _onShellTabChanged() {
    _maybeStartLoading();
  }

  void _maybeStartLoading() {
    if (!ShellTabVisibility.chatsActive) return;
    if (_started) return;
    _started = true;
    _resetPollTimer();
    _load();
  }

  void _resetPollTimer() {
    _pollTimer?.cancel();
    if (!_started) return;
    final seconds = UserRealtimeService.instance.connected.value ? 90 : 45;
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!_appPaused && !_loading && ShellTabVisibility.chatsActive) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    ShellTabVisibility.activeIndex.removeListener(_onShellTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _signalSub?.cancel();
    _realtimeSub?.cancel();
    if (_realtimeConnectedListener != null) {
      UserRealtimeService.instance.connected
          .removeListener(_realtimeConnectedListener!);
    }
    if (_apiReachabilityListener != null) {
      ApiReachabilityService.instance.isApiReachable
          .removeListener(_apiReachabilityListener!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
    if (!_appPaused) {
      unawaited(ApiReachabilityService.instance.warmUp(force: kIsWeb));
    }
  }

  List<Channel> _uniqueChannels(List<Channel> channels) {
    final seen = <int>{};
    final out = <Channel>[];
    for (final c in channels) {
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      if (a is ChatInboxEntry && b is ChatInboxEntry) {
        if (a.chat.pinned != b.chat.pinned) {
          return a.chat.pinned ? -1 : 1;
        }
      }
      return b.sortAt.compareTo(a.sortAt);
    });
  }

  ChatConversation? _extractSavedChat(List<ChatConversation> chats) {
    for (final c in chats) {
      if (c.isSaved) return c;
    }
    return null;
  }

  List<ChatConversation> _withoutSavedChat(
    List<ChatConversation> chats, [
    ChatConversation? saved,
  ]) {
    final savedId = saved?.id;
    return chats
        .where((c) => !c.isSaved && (savedId == null || c.id != savedId))
        .toList(growable: false);
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      final cached =
          ChatCacheService.peekConversations() ??
          await ChatCacheService.loadConversations();
      if (!mounted || seq != _loadSeq) return;
      if (cached != null && cached.isNotEmpty) {
        final cachedSaved = _extractSavedChat(cached);
        final cachedRest = _withoutSavedChat(cached, cachedSaved);
        setState(() {
          if (cachedSaved != null) _savedChat = cachedSaved;
          _entries
            ..clear()
            ..addAll(cachedRest.map(ChatInboxEntry.new));
          _loading = false;
          _error = null;
          _servingFromCache = true;
        });
      } else {
        setState(() {
          _loading = true;
          _error = null;
          _chatsPartialError = null;
        });
      }
    }

    List<ChatConversation> chats = [];
    Object? chatsError;
    List<Channel> channels = [];
    Object? channelsError;
    var favoriteIds = <int>{};
    var archivedChannelIds = <int>{};

    await Future.wait<void>([
      () async {
        try {
          chats = await ChatService.listConversations();
        } catch (e) {
          chatsError = e;
          if (kDebugMode) debugPrint('Chats load failed: $e');
        }
      }(),
      () async {
        try {
          await ChannelSheetPrefs.syncFromServer();
          favoriteIds = (await ChannelSheetPrefs.listFavoriteIds()).toSet();
          archivedChannelIds = await ChannelSheetPrefs.listArchivedIds();
          final owned = await ChannelService.listChannels(
            limit: 50,
            offset: 0,
            mine: true,
            withLastPost: true,
          );
          final subscribed = await ChannelService.listChannels(
            limit: 50,
            offset: 0,
            subscribed: true,
            withLastPost: true,
          );
          channels = _uniqueChannels([...owned.items, ...subscribed.items])
              .where((c) => !archivedChannelIds.contains(c.id))
              .toList();
        } catch (e) {
          channelsError = e;
          if (kDebugMode) debugPrint('Channels load failed: $e');
        }
      }(),
    ]);

    if (!mounted || seq != _loadSeq) return;

    final resolvedSaved = _extractSavedChat(chats) ?? _savedChat;
    chats = _withoutSavedChat(chats, resolvedSaved);

    if (chats.isEmpty &&
        channels.isEmpty &&
        resolvedSaved == null) {
      final err = chatsError ?? channelsError;
      if (err != null) {
        unawaited(FeedLoadHelper.clearSessionIfExpired(err));
      }
      setState(() {
        _entries.clear();
        _recommended = [];
        _error = err;
        _chatsPartialError = null;
        _loading = false;
        _servingFromCache = false;
      });
      return;
    }

    final channelEntries = channels
        .map(
          (c) => ChannelInboxEntry(
            channel: c,
            isFavorite: favoriteIds.contains(c.id),
          ),
        )
        .toList();
    channelEntries.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return b.sortAt.compareTo(a.sortAt);
    });

    final entries = <InboxHubEntry>[
      ...chats.map(ChatInboxEntry.new),
      ...channelEntries,
    ]..sort((a, b) {
        final aFav = a is ChannelInboxEntry && a.isFavorite;
        final bFav = b is ChannelInboxEntry && b.isFavorite;
        if (aFav != bFav) return aFav ? -1 : 1;
        if (a is ChatInboxEntry && b is ChatInboxEntry) {
          if (a.chat.pinned != b.chat.pinned) {
            return a.chat.pinned ? -1 : 1;
          }
          return b.sortAt.compareTo(a.sortAt);
        }
        if (a is ChannelInboxEntry && b is ChannelInboxEntry) {
          return b.sortAt.compareTo(a.sortAt);
        }
        return b.sortAt.compareTo(a.sortAt);
      });

    setState(() {
      if (resolvedSaved != null) _savedChat = resolvedSaved;
      _entries
        ..clear()
        ..addAll(entries);
      _error = null;
      _chatsPartialError =
          chatsError != null && channels.isNotEmpty ? chatsError : null;
      _loading = false;
      _servingFromCache = false;
    });

    unawaited(
      _loadRecommendedChannels(
        seq: seq,
        channels: channels,
        archivedChannelIds: archivedChannelIds,
      ),
    );
  }

  Future<void> _loadRecommendedChannels({
    required int seq,
    required List<Channel> channels,
    required Set<int> archivedChannelIds,
  }) async {
    try {
      final rec = await ChannelService.listChannels(
        limit: 8,
        offset: 0,
        recommended: true,
        withLastPost: true,
      );
      if (!mounted || seq != _loadSeq) return;
      final known = channels.map((c) => c.id).toSet();
      final recommended = rec.items
          .where(
            (c) => !known.contains(c.id) && !archivedChannelIds.contains(c.id),
          )
          .toList();
      if (!mounted || seq != _loadSeq) return;
      setState(() => _recommended = recommended);
    } catch (_) {}
  }

  void _onChannelSortAtChanged(ChannelInboxEntry entry, DateTime sortAt) {
    if (!mounted) return;
    setState(() {
      entry.sortAt = sortAt;
      _sortEntries();
    });
  }

  List<InboxHubEntry> get _folderFilteredEntries {
    final folder = _activeFolder;
    if (folder == null) return _entries;
    return _entries.where((e) => _entryMatchesFolder(e, folder)).toList();
  }

  Future<void> _openSavedChat() async {
    if (_openingSaved) return;
    setState(() => _openingSaved = true);
    try {
      var conv = _savedChat;
      if (conv == null || conv.id <= 0) {
        conv = await ChatService.ensureSavedChat();
        if (!mounted) return;
        setState(() => _savedChat = conv);
      }
      await context.push(ChatThreadRoute.pathFor(conv), extra: conv);
      if (mounted) _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _openingSaved = false);
    }
  }

  List<InboxHubEntry> get _visibleEntries {
    final base = _folderFilteredEntries
        .where(
          (e) => !(e is ChatInboxEntry && e.chat.isSaved),
        )
        .toList();
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((e) {
      if (e is ChatInboxEntry) {
        final preview = e.chat.lastMessage?.content ?? '';
        return e.chat.displayTitle.toLowerCase().contains(q) ||
            preview.toLowerCase().contains(q);
      }
      if (e is ChannelInboxEntry) {
        return e.channel.name.toLowerCase().contains(q) ||
            (e.channel.lastPostPreview?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  List<Channel> get _visibleRecommended {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _recommended;
    return _recommended
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _openChannel(int channelId) async {
    await context.push(ChannelDetailRoute.pathFor(channelId));
    if (mounted) _load();
  }

  Future<void> _archiveChannelFromHub(Channel channel) async {
    try {
      await ChannelSheetPrefs.setArchived(channel.id, true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${channel.name}» в архиве')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _showChannelHubActions(Channel channel) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Добавить в папку'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToFolderSheet(channelId: channel.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('В архив'),
              subtitle: const Text('Скрыть из списка чатов'),
              onTap: () {
                Navigator.pop(ctx);
                _archiveChannelFromHub(channel);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Открыть канал'),
              onTap: () {
                Navigator.pop(ctx);
                _openChannel(channel.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveChannelFromHub(Channel channel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отписаться от канала?'),
        content: Text(
          '«${channel.name}» исчезнет из списка. Вы сможете подписаться снова.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ChannelService.leaveChannel(channel.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Вы вышли из «${channel.name}»')),
      );
      await _load(silent: true);
      ref.read(shellChatBadgeRefreshProvider.notifier).state++;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _archiveChatFromHub(ChatConversation chat) async {
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    try {
      await ChatService.setArchived(conversationId: chat.id, archived: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${chat.displayTitle}» в архиве')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _hubActionChatId = null);
    }
  }

  Future<void> _togglePinFromHub(ChatConversation chat) async {
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    final next = !chat.pinned;
    try {
      await ChatService.setPinned(conversationId: chat.id, pinned: next);
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _hubActionChatId = null);
    }
  }

  Future<void> _toggleMuteFromHub(ChatConversation chat) async {
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    final next = !chat.muted;
    try {
      await ChatService.setMuted(conversationId: chat.id, muted: next);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Чат без звука' : 'Уведомления включены'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _hubActionChatId = null);
    }
  }

  Future<void> _deleteChatFromHub(ChatConversation chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          chat.isGroup
              ? 'Вы выйдете из «${chat.displayTitle}». История останется у других участников.'
              : 'Чат «${chat.displayTitle}» исчезнет из списка. При новом сообщении диалог можно начать снова.',
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
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    try {
      await ChatService.deleteConversation(conversationId: chat.id);
      unawaited(ChatCacheService.clearDraft(chat.id));
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${chat.displayTitle}» удалён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _hubActionChatId = null);
    }
  }

  Future<void> _markUnreadFromHub(ChatConversation chat) async {
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    try {
      await ChatService.markUnread(conversationId: chat.id);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чат помечен непрочитанным')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _hubActionChatId = null);
    }
  }

  void _showChatHubActions(ChatConversation chat) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!chat.isSaved) ...[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Добавить в папку'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToFolderSheet(conversationId: chat.id);
                },
              ),
              ListTile(
                leading: Icon(
                  chat.muted
                      ? Icons.notifications_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(chat.muted ? 'Включить уведомления' : 'Без звука'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleMuteFromHub(chat);
                },
              ),
              ListTile(
                leading: Icon(
                  chat.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(chat.pinned ? 'Открепить' : 'Закрепить'),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePinFromHub(chat);
                },
              ),
              ListTile(
                leading: const Icon(Icons.mark_chat_unread_outlined),
                title: const Text('Пометить непрочитанным'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markUnreadFromHub(chat);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('В архив'),
                onTap: () {
                  Navigator.pop(ctx);
                  _archiveChatFromHub(chat);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Удалить чат',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteChatFromHub(chat);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: const Text('Избранное'),
                subtitle: const Text(
                  'Личное хранилище — только вы видите эти сообщения',
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _hubOfflineBanner() {
    final scheme = Theme.of(context).colorScheme;
    final apiOk = ApiReachabilityService.instance.isApiReachable.value;
    final message = apiOk
        ? 'Показан сохранённый список чатов'
        : 'Нет связи с сервером — сохранённый список чатов';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onFolderLongPress(ChatFolder folder) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Изменить папку'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditFolder(folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Удалить папку',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await ChatFolderStore.deleteFolder(folder.id);
                if (!mounted) return;
                if (_selectedFolderId == folder.id) _selectFolder(null);
                await _loadFolders();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(channelsMainListRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });
    ref.listen<int>(chatsHubRefreshProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });

    if (!_started) {
      return const SizedBox.shrink();
    }
    if (_loading && _entries.isEmpty) {
      return const ChatInboxSkeleton();
    }
    if (_error != null && !_showSavedPinned) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить',
        subtitle: userVisibleError(_error!),
        action: FilledButton(onPressed: _load, child: const Text('Повторить')),
      );
    }
    if (_entries.isEmpty && !_showSavedPinned) {
      return AppEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Пока пусто',
        subtitle: 'Начните диалог или подпишитесь на канал в каталоге.',
        action: FilledButton.icon(
          onPressed: () => context.push(ChannelsManagementRoute.path),
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Каталог каналов'),
        ),
      );
    }

    final visible = _visibleEntries;
    final visibleRec = _visibleRecommended;
    if (visible.isEmpty && visibleRec.isEmpty && !_showSavedPinned) {
      final q = widget.searchQuery.trim();
      final folder = _activeFolder;
      if (q.isEmpty && folder != null) {
        return AppEmptyState(
          icon: Icons.folder_open_outlined,
          title: 'Папка пуста',
          subtitle:
              'Добавьте чаты через удержание → «Добавить в папку» или измените папку.',
          action: FilledButton(
            onPressed: () => _openEditFolder(folder),
            child: const Text('Изменить папку'),
          ),
        );
      }
      if (q.isEmpty && _entries.isNotEmpty) {
        return AppEmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Нет чатов',
          subtitle: 'В этой папке пока ничего нет.',
          action: FilledButton(
            onPressed: () => _selectFolder(null),
            child: const Text('Все чаты'),
          ),
        );
      }
      return AppEmptyState(
        icon: Icons.search_off,
        title: 'Ничего не найдено',
        subtitle: q.isNotEmpty
            ? 'Попробуйте другой запрос или поищите во вкладке «Контакты».'
            : 'Попробуйте другой запрос.',
        action: q.isNotEmpty
            ? FilledButton(
                onPressed: widget.onSwitchToContacts,
                child: const Text('Контакты'),
              )
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_showGesturesHint && widget.searchQuery.trim().isEmpty)
            SliverToBoxAdapter(
              child: ChatsHubGesturesHint(onDismiss: _dismissGesturesHint),
            ),
          if (_servingFromCache)
            SliverToBoxAdapter(child: _hubOfflineBanner()),
          if (widget.searchQuery.trim().isEmpty)
            SliverToBoxAdapter(
            child: ChatHubFolderBar(
              folders: _folders,
              selectedFolderId: _selectedFolderId,
              onSelectFolder: _selectFolder,
              onCreateFolder: _openCreateFolder,
              onManageFolders: _openManageFolders,
              onFolderLongPress: _onFolderLongPress,
            ),
          ),
          if (_chatsPartialError != null)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text(
                  'Личные диалоги не загрузились: '
                  '${userVisibleError(_chatsPartialError!)}',
                ),
                leading: const Icon(Icons.warning_amber_outlined),
                actions: [
                  TextButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          if (_showSavedPinned)
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatHubTile(
                    chat: _savedChatTile,
                    onTap: _openSavedChat,
                    onLongPress: () => _showChatHubActions(_savedChatTile),
                  ),
                  if (visible.isNotEmpty)
                    const Divider(height: 1, indent: 72),
                ],
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index.isOdd) {
                  return const Divider(height: 1, indent: 72);
                }
                final entry = visible[index ~/ 2];
                if (entry is ChatInboxEntry) {
                  final chat = entry.chat;
                  return ChatInboxSlidable(
                    chatId: chat.id,
                    muted: chat.muted,
                    enabled: !chat.isSaved,
                    onArchive: () => _archiveChatFromHub(chat),
                    onToggleMute: () => _toggleMuteFromHub(chat),
                    onDelete: () => _deleteChatFromHub(chat),
                    child: ChatHubTile(
                      chat: chat,
                      onTap: () async {
                        await context.push(
                          ChatThreadRoute.pathFor(chat),
                          extra: chat,
                        );
                        if (mounted) _load();
                      },
                      onLongPress: () => _showChatHubActions(chat),
                    ),
                  );
                }
                final channelEntry = entry as ChannelInboxEntry;
                return ChannelInboxSlidable(
                  key: ValueKey('channel_${channelEntry.channel.id}'),
                  channelId: channelEntry.channel.id,
                  onArchive: () =>
                      _archiveChannelFromHub(channelEntry.channel),
                  onLeave: () => _leaveChannelFromHub(channelEntry.channel),
                  child: ChannelInboxTile(
                    channel: channelEntry.channel,
                    onSortAtChanged: (dt) =>
                        _onChannelSortAtChanged(channelEntry, dt),
                    onTap: () => _openChannel(channelEntry.channel.id),
                    onMarkedSeen: () {
                      ref.read(shellChatBadgeRefreshProvider.notifier).state++;
                    },
                    onLongPress: () =>
                        _showChannelHubActions(channelEntry.channel),
                  ),
                );
              },
              childCount: visible.isEmpty ? 0 : visible.length * 2 - 1,
            ),
          ),
          if (visibleRec.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Рекомендации',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: visibleRec.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final ch = visibleRec[i];
                    return ChatHubRecommendedChannelChip(
                      channel: ch,
                      onTap: () => _openChannel(ch.id),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
          ),
        ],
      ),
    );
  }
}
