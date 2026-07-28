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
import '../../../../services/chat_thread_ui_prefs.dart';
import '../../../../services/user_realtime_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_empty_state.dart';
import '../../../../widgets/chat_inbox_skeleton.dart';
import '../../../../widgets/telegram_ui.dart';
import '../../../channels/application/channels_list_refresh_provider.dart';
import '../../../navigation/application/shell_chat_badge_refresh_provider.dart';
import '../../../navigation/application/shell_tab_visibility.dart';
import '../../application/chat_realtime_signals.dart';
import '../../application/chats_hub_refresh_provider.dart';
import '../../widgets/inbox_slidable_tile.dart';
import '../chat_archived_screen.dart';
import '../chat_folder_edit_screen.dart';
import '../chat_folders_manage_sheet.dart';
import 'chat_mute_duration_sheet.dart';
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
  ConsumerState<ChatsHubAllInboxTab> createState() =>
      _ChatsHubAllInboxTabState();
}

class _ChatsHubAllInboxTabState extends ConsumerState<ChatsHubAllInboxTab>
    with WidgetsBindingObserver {
  final _entries = <InboxHubEntry>[];
  List<Channel> _recommended = [];
  List<ChatJoinRequestsInboxItem> _joinRequestsInbox = [];
  bool _loading = false;
  bool _started = false;
  Object? _error;
  Object? _chatsPartialError;
  Object? _joinInboxPartialError;
  int _loadSeq = 0;
  int? _hubActionChatId;
  Timer? _pollTimer;
  StreamSubscription<void>? _signalSub;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;
  VoidCallback? _apiReachabilityListener;
  VoidCallback? _apiConnectingListener;
  VoidCallback? _realtimeConnectedListener;
  bool _appPaused = false;
  List<ChatFolder> _folders = [];
  int? _selectedFolderId;
  bool _showGesturesHint = false;
  bool _servingFromCache = false;
  Map<int, ChatDraft> _drafts = {};
  /// conversationId → (userId → typing expires at, local clock).
  final Map<int, Map<int, DateTime>> _typingUntilByUser = {};
  /// conversationId → (userId → typing|recording).
  final Map<int, Map<int, String>> _typingActivityByUser = {};
  Timer? _typingTicker;

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
        conversationIds: conversationId != null ? [conversationId] : const [],
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
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
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
    final filters = folder.filters;
    if (entry is ChatInboxEntry) {
      final chat = entry.chat;
      if (chat.isSaved) return false;
      final explicit = folder.containsConversation(chat.id);
      if (!explicit) {
        if (filters.isEmpty) return false;
        if (filters.hasTypeFilter) {
          final typeOk = (filters.groups && chat.isGroup) ||
              (filters.direct && !chat.isGroup);
          if (!typeOk) return false;
        } else if (!filters.unreadOnly && !filters.hasExcludeFilter) {
          return false;
        } else if (!filters.unreadOnly && filters.hasExcludeFilter) {
          // Exclude-only filters still need a type or unread rule to match.
          return false;
        }
        if (filters.unreadOnly && chat.unreadCount <= 0) return false;
      }
      if (filters.excludeMuted && chat.muted) return false;
      if (filters.excludeArchived && chat.archived) return false;
      if (filters.excludeBots &&
          !chat.isGroup &&
          (chat.peer?.isBot ?? false)) {
        return false;
      }
      return true;
    }
    if (entry is ChannelInboxEntry) {
      final explicit = folder.containsChannel(entry.channel.id);
      if (!explicit) {
        if (filters.isEmpty) return false;
        if (filters.hasTypeFilter) {
          if (!filters.channels) return false;
        } else if (!filters.unreadOnly && !filters.hasExcludeFilter) {
          return false;
        } else if (!filters.unreadOnly && filters.hasExcludeFilter) {
          return false;
        }
        if (filters.unreadOnly && entry.channel.inboxUnreadPosts <= 0) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  Map<int, int> _folderUnreadCounts() {
    final out = <int, int>{};
    for (final folder in _folders) {
      var total = 0;
      for (final entry in _entries) {
        if (!_entryMatchesFolder(entry, folder)) continue;
        if (entry is ChatInboxEntry) {
          total += entry.chat.unreadCount;
        } else if (entry is ChannelInboxEntry) {
          total += entry.channel.inboxUnreadPosts;
        }
      }
      out[folder.id] = total;
    }
    return out;
  }

  ChatConversation? _savedChat;
  bool _openingSaved = false;
  int _archivedCount = 0;
  int _archivedUnread = 0;
  String? _archivedPreview;

  bool get _showSavedPinned =>
      widget.searchQuery.trim().isEmpty && _selectedFolderId == null;

  bool get _showArchiveRow =>
      widget.searchQuery.trim().isEmpty &&
      _selectedFolderId == null &&
      _archivedCount > 0;

  ChatConversation get _savedChatTile =>
      _savedChat ??
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
    unawaited(_refreshDrafts());
  }

  Future<void> _refreshDrafts() async {
    final ids = <int>[
      for (final entry in _entries)
        if (entry is ChatInboxEntry) entry.chat.id,
      if (_savedChat != null) _savedChat!.id,
    ];
    final drafts = await ChatCacheService.loadDrafts(ids);
    try {
      final cloud = await ChatService.listCloudDraftsByConversation();
      for (final entry in cloud.entries) {
        final local = drafts[entry.key];
        final remote = entry.value;
        final localAt = local?.updatedAt;
        final remoteAt = remote.updatedAt;
        if (local == null ||
            local.isEmpty ||
            (remoteAt != null &&
                (localAt == null || remoteAt.isAfter(localAt)))) {
          drafts[entry.key] = remote;
          unawaited(
            ChatCacheService.saveDraft(
              entry.key,
              remote.text,
              replyToMessageId: remote.replyToMessageId,
              updatedAt: remote.updatedAt,
            ),
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _drafts = drafts);
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
      if (!mounted || !_started) return;

      if (event.event == 'chat.typing') {
        final cid = event.conversationId;
        if (cid == null) return;
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
        for (var i = 0; i < _entries.length; i++) {
          final entry = _entries[i];
          if (entry is! ChatInboxEntry) continue;
          final peer = entry.chat.peer;
          if (peer == null || peer.id != uid) continue;
          _entries[i] = ChatInboxEntry(
            entry.chat.copyWith(peer: peer.copyWith(lastSeenAt: seen)),
          );
          changed = true;
        }
        if (changed && mounted) setState(() {});
        return;
      }

      if (!ShellTabVisibility.chatsActive || _loading) return;
      if (event.event == 'chat.inbox' ||
          event.event == 'chat.message_hidden' ||
          event.event == 'chat.join_request.new' ||
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
      if (!mounted) return;
      setState(() {}); // offline banner visibility
      if (!ApiReachabilityService.instance.isApiReachable.value) return;
      if (_started && ShellTabVisibility.chatsActive && !_loading) {
        _load(silent: true);
      }
    };
    ApiReachabilityService.instance.isApiReachable
        .addListener(_apiReachabilityListener!);
    _apiConnectingListener = () {
      if (mounted) setState(() {});
    };
    ApiReachabilityService.instance.isApiConnecting
        .addListener(_apiConnectingListener!);
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

  String? _displayNameForTyping(ChatConversation chat, int userId) {
    if (userId <= 0) return null;
    final peer = chat.peer;
    if (peer != null && peer.id == userId) {
      final name = peer.displayName.trim();
      if (name.isNotEmpty) return name;
    }
    for (final m in chat.membersPreview) {
      if (m.id == userId) {
        final name = m.displayName.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  String? _typingLabelFor(int conversationId) {
    final byUser = _typingUntilByUser[conversationId];
    if (byUser == null || byUser.isEmpty) return null;
    final now = DateTime.now();
    final activeIds =
        byUser.entries.where((e) => e.value.isAfter(now)).map((e) => e.key);
    final active = activeIds.toList();
    if (active.isEmpty) return null;
    final activities = _typingActivityByUser[conversationId] ?? const {};
    final recording = active.any((id) => activities[id] == 'recording');

    ChatConversation? chat;
    for (final e in _entries) {
      if (e is ChatInboxEntry && e.chat.id == conversationId) {
        chat = e.chat;
        break;
      }
    }
    if (chat == null || !chat.isGroup) {
      return recording ? 'записывает голосовое…' : 'печатает…';
    }

    final names = <String>[];
    for (final id in active) {
      final name = _displayNameForTyping(chat, id);
      if (name == null || name.isEmpty) continue;
      names.add(name.split(' ').first);
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
    ShellTabVisibility.activeIndex.removeListener(_onShellTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingTicker?.cancel();
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
    if (_apiConnectingListener != null) {
      ApiReachabilityService.instance.isApiConnecting
          .removeListener(_apiConnectingListener!);
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
      final cached = ChatCacheService.peekConversations() ??
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
          _joinInboxPartialError = null;
        });
      }
    }

    List<ChatConversation> chats = [];
    Object? chatsError;
    List<Channel> channels = [];
    Object? channelsError;
    List<ChatJoinRequestsInboxItem> joinInbox = [];
    Object? joinInboxError;
    var favoriteIds = <int>{};
    var mutedChannelIds = <int>{};
    var archivedChannelIds = <int>{};

    final channelsFuture = () async {
      try {
        await ChannelSheetPrefs.syncFromServer();
        favoriteIds = (await ChannelSheetPrefs.listFavoriteIds()).toSet();
        mutedChannelIds = await ChannelSheetPrefs.listMutedIds();
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
    }();

    List<ChatConversation> archivedChats = const [];
    try {
      chats = await ChatService.listConversations();
      final expired = await _expireTimedMutes(chats);
      if (expired > 0) {
        chats = await ChatService.listConversations();
      }
    } catch (e) {
      chatsError = e;
      if (kDebugMode) debugPrint('Chats load failed: $e');
    }
    try {
      archivedChats = await ChatService.listConversations(archived: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Archived chats load failed: $e');
    }
    try {
      joinInbox = await ChatService.listJoinRequestsInbox(limit: 50);
    } catch (e) {
      joinInboxError = e;
      if (kDebugMode) debugPrint('Join inbox load failed: $e');
    }
    if (!mounted || seq != _loadSeq) return;

    final earlySaved = _extractSavedChat(chats) ?? _savedChat;
    final earlyChats = _withoutSavedChat(chats, earlySaved);
    if (earlyChats.isNotEmpty || earlySaved != null) {
      setState(() {
        if (earlySaved != null) _savedChat = earlySaved;
        _entries
          ..clear()
          ..addAll(earlyChats.map(ChatInboxEntry.new));
        _error = null;
        _chatsPartialError = null;
        _loading = false;
        _servingFromCache = false;
      });
      unawaited(_refreshDrafts());
    }

    await channelsFuture;

    if (!mounted || seq != _loadSeq) return;

    final resolvedSaved = _extractSavedChat(chats) ?? _savedChat;
    chats = _withoutSavedChat(chats, resolvedSaved);

    if (chats.isEmpty && channels.isEmpty && resolvedSaved == null) {
      final err = chatsError ?? channelsError;
      if (err != null) {
        unawaited(FeedLoadHelper.clearSessionIfExpired(err));
      }
      setState(() {
        _entries.clear();
        _recommended = [];
        _joinRequestsInbox = [];
        _error = err;
        _chatsPartialError = null;
        _joinInboxPartialError = null;
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
            notificationsEnabled: !mutedChannelIds.contains(c.id),
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

    final archivedPreview = archivedChats.isEmpty
        ? null
        : () {
            final last = archivedChats.first;
            final title = last.displayTitle;
            final body = chatHubBodyPreview(
              last.lastMessage,
              isSaved: last.isSaved,
            );
            if (body.isEmpty) return title;
            return '$title — $body';
          }();
    final archivedUnread = archivedChats.fold<int>(
      0,
      (sum, c) => sum + c.unreadCount,
    );

    setState(() {
      if (resolvedSaved != null) _savedChat = resolvedSaved;
      _entries
        ..clear()
        ..addAll(entries);
      _archivedCount = archivedChats.length;
      _archivedUnread = archivedUnread;
      _archivedPreview = archivedPreview;
      _error = null;
      _chatsPartialError =
          chatsError != null && channels.isNotEmpty ? chatsError : null;
      _joinRequestsInbox = joinInbox;
      _joinInboxPartialError = joinInboxError;
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

  Future<void> _openArchivedFromHub() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChatArchivedScreen()),
    );
    if (mounted) unawaited(_load(silent: true));
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

  Future<void> _reviewJoinInboxItem(
    ChatJoinRequestsInboxItem item, {
    required bool approve,
  }) async {
    try {
      await ChatService.reviewGroupJoinRequest(
        conversationId: item.conversation.id,
        requestId: item.id,
        approve: approve,
      );
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Заявка принята' : 'Заявка отклонена',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showAllJoinRequestsInbox() async {
    if (_joinRequestsInbox.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Заявки в модерацию (${_joinRequestsInbox.length})',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: _joinRequestsInbox.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _joinRequestsInbox[index];
                      return ListTile(
                        title: Text(
                          '${item.user.displayName} → ${item.conversation.displayTitle}',
                        ),
                        subtitle: Text(
                          '${item.requestedAt.day.toString().padLeft(2, '0')}.'
                          '${item.requestedAt.month.toString().padLeft(2, '0')}.'
                          '${item.requestedAt.year}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _reviewJoinInboxItem(
                                  item,
                                  approve: false,
                                );
                              },
                              child: const Text('Нет'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _reviewJoinInboxItem(
                                  item,
                                  approve: true,
                                );
                              },
                              child: const Text('Да'),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push(
                            ChatThreadRoute.pathFor(item.conversation),
                            extra: item.conversation,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    return _recommended.where((c) => c.name.toLowerCase().contains(q)).toList();
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

  Future<void> _toggleChannelMuteFromHub(Channel channel) async {
    try {
      final enabled =
          await ChannelSheetPrefs.getNotificationsEnabled(channel.id);
      await ChannelSheetPrefs.setNotificationsEnabled(channel.id, !enabled);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '«${channel.name}» без звука'
                : 'Уведомления «${channel.name}» включены',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleChannelFavoriteFromHub(Channel channel) async {
    try {
      final isFav = await ChannelSheetPrefs.getFavorite(channel.id);
      await ChannelSheetPrefs.setFavorite(channel.id, !isFav);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFav
                ? '«${channel.name}» убран из избранного'
                : '«${channel.name}» в избранном',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _showChannelHubActions(
    Channel channel, {
    bool isFavorite = false,
    bool notificationsEnabled = true,
  }) {
    showTelegramActionSheet<void>(
      context: context,
      title: 'Действия',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.folder_outlined,
          title: 'Добавить в папку',
          onTap: () => _showAddToFolderSheet(channelId: channel.id),
        ),
        TelegramActionSheetAction(
          icon: isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          title: isFavorite ? 'Убрать из избранного' : 'В избранное',
          onTap: () => _toggleChannelFavoriteFromHub(channel),
        ),
        TelegramActionSheetAction(
          icon: notificationsEnabled
              ? Icons.notifications_off_outlined
              : Icons.notifications_outlined,
          title: notificationsEnabled
              ? 'Без звука'
              : 'Включить уведомления',
          onTap: () => _toggleChannelMuteFromHub(channel),
        ),
        TelegramActionSheetAction(
          icon: Icons.archive_outlined,
          title: 'В архив',
          subtitle: 'Скрыть из списка чатов',
          onTap: () => _archiveChannelFromHub(channel),
        ),
        TelegramActionSheetAction(
          icon: Icons.open_in_new_outlined,
          title: 'Открыть канал',
          onTap: () => _openChannel(channel.id),
        ),
      ],
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

  Future<void> _toggleMuteFromHub(ChatConversation chat) async {
    if (_hubActionChatId != null) return;
    final choice = await showChatMuteDurationSheet(
      context,
      currentlyMuted: chat.muted,
    );
    if (choice == null || !mounted) return;
    setState(() => _hubActionChatId = chat.id);
    try {
      late final String snack;
      if (choice.unmute) {
        await ChatService.setMuted(conversationId: chat.id, muted: false);
        await ChatThreadUiPrefs.setMuteUntil(chat.id, null);
        snack = choice.snackLabel;
      } else {
        await ChatService.setMuted(
          conversationId: chat.id,
          muted: true,
          mutedUntil: choice.until,
        );
        await ChatThreadUiPrefs.setMuteUntil(chat.id, choice.until);
        snack = choice.snackLabel;
      }
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snack)),
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
    if (_hubActionChatId != null) return;
    setState(() => _hubActionChatId = chat.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(chat.isGroup ? 'Выйти из группы?' : 'Удалить чат?'),
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
            child: Text(chat.isGroup ? 'Выйти' : 'Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      if (mounted) setState(() => _hubActionChatId = null);
      return;
    }
    try {
      await ChatService.deleteConversation(conversationId: chat.id);
      unawaited(ChatCacheService.clearDraft(chat.id));
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chat.isGroup
                ? 'Вы вышли из «${chat.displayTitle}»'
                : '«${chat.displayTitle}» удалён',
          ),
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
    showTelegramActionSheet<void>(
      context: context,
      title: 'Действия',
      actions: chat.isSaved
          ? [
              TelegramActionSheetAction(
                icon: Icons.bookmark_rounded,
                title: 'Избранное',
                subtitle: 'Личное хранилище — только вы видите эти сообщения',
                onTap: _openSavedChat,
              ),
            ]
          : [
              TelegramActionSheetAction(
                icon: Icons.folder_outlined,
                title: 'Добавить в папку',
                onTap: () => _showAddToFolderSheet(conversationId: chat.id),
              ),
              TelegramActionSheetAction(
                icon: chat.muted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                title: chat.muted ? 'Включить уведомления' : 'Без звука',
                onTap: () => _toggleMuteFromHub(chat),
              ),
              TelegramActionSheetAction(
                icon: chat.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                title: chat.pinned ? 'Открепить' : 'Закрепить',
                onTap: () => _togglePinFromHub(chat),
              ),
              TelegramActionSheetAction(
                icon: Icons.mark_chat_unread_outlined,
                title: 'Пометить непрочитанным',
                onTap: () => _markUnreadFromHub(chat),
              ),
              TelegramActionSheetAction(
                icon: Icons.archive_outlined,
                title: 'В архив',
                onTap: () => _archiveChatFromHub(chat),
              ),
              if (!chat.isGroup && chat.peer != null)
                TelegramActionSheetAction(
                  icon: chat.peerBlockedByMe
                      ? Icons.lock_open_outlined
                      : Icons.block_outlined,
                  title: chat.peerBlockedByMe
                      ? 'Разблокировать'
                      : 'Заблокировать',
                  destructive: !chat.peerBlockedByMe,
                  onTap: () => _toggleBlockFromHub(chat),
                ),
              TelegramActionSheetAction(
                icon: chat.isGroup ? Icons.logout : Icons.delete_outline,
                title: chat.isGroup ? 'Выйти из группы' : 'Удалить чат',
                destructive: true,
                onTap: () => _deleteChatFromHub(chat),
              ),
            ],
    );
  }

  Future<void> _toggleBlockFromHub(ChatConversation chat) async {
    final peer = chat.peer;
    if (peer == null || _hubActionChatId != null) return;
    if (!chat.peerBlockedByMe) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Заблокировать?'),
          content: Text(
            '${peer.displayName} не сможет писать вам и видеть ваш профиль в чатах.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Заблокировать'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _hubActionChatId = chat.id);
    try {
      if (chat.peerBlockedByMe) {
        await ChatService.unblockUser(peer.id);
      } else {
        await ChatService.blockUser(peer.id);
      }
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chat.peerBlockedByMe
                ? '${peer.displayName} разблокирован'
                : '${peer.displayName} заблокирован',
          ),
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

  Widget _hubOfflineBanner() {
    final scheme = Theme.of(context).colorScheme;
    final connecting = ApiReachabilityService.instance.isApiConnecting.value;
    final message = connecting
        ? 'Соединение…'
        : 'Ожидание сети…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (connecting)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSecondaryContainer,
                  ),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
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
    showTelegramActionSheet<void>(
      context: context,
      title: 'Действия',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.edit_outlined,
          title: 'Изменить папку',
          onTap: () => _openEditFolder(folder),
        ),
        TelegramActionSheetAction(
          icon: Icons.delete_outline,
          title: 'Удалить папку',
          destructive: true,
          onTap: () async {
            await ChatFolderStore.deleteFolder(folder.id);
            if (!mounted) return;
            if (_selectedFolderId == folder.id) _selectFolder(null);
            await _loadFolders();
          },
        ),
      ],
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
          // Silent cache while online (Telegram-style). Banner only when offline.
          if (_servingFromCache &&
              !ApiReachabilityService.instance.isApiReachable.value)
            SliverToBoxAdapter(child: _hubOfflineBanner()),
          if (widget.searchQuery.trim().isEmpty)
            SliverToBoxAdapter(
              child: ChatHubFolderBar(
                folders: _folders,
                selectedFolderId: _selectedFolderId,
                folderUnreadCounts: _folderUnreadCounts(),
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
          if (_joinInboxPartialError != null)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text(
                  'Заявки на вступление не загрузились: '
                  '${userVisibleError(_joinInboxPartialError!)}',
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
          if (widget.searchQuery.trim().isEmpty &&
              _joinRequestsInbox.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiaryContainer
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.pending_actions_outlined),
                          title: const Text('Заявки в модерацию'),
                          subtitle: Text(
                            '${_joinRequestsInbox.length} ожидают решения',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showAllJoinRequestsInbox,
                        ),
                        ..._joinRequestsInbox.take(3).map((item) {
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${item.user.displayName} -> ${item.conversation.displayTitle}',
                            ),
                            subtitle: Text(
                              '${item.requestedAt.day.toString().padLeft(2, '0')}.${item.requestedAt.month.toString().padLeft(2, '0')}.${item.requestedAt.year}',
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () => _reviewJoinInboxItem(
                                    item,
                                    approve: false,
                                  ),
                                  child: const Text('Нет'),
                                ),
                                FilledButton(
                                  onPressed: () => _reviewJoinInboxItem(
                                    item,
                                    approve: true,
                                  ),
                                  child: const Text('Да'),
                                ),
                              ],
                            ),
                            onTap: () => context.push(
                              ChatThreadRoute.pathFor(item.conversation),
                              extra: item.conversation,
                            ),
                          );
                        }),
                        if (_joinRequestsInbox.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TextButton(
                              onPressed: _showAllJoinRequestsInbox,
                              child: Text(
                                'И ещё ${_joinRequestsInbox.length - 3} заявок',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showSavedPinned)
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatHubTile(
                    chat: _savedChatTile,
                    draftText: _drafts[_savedChatTile.id]?.hubPreview,
                    draftHasReply: _drafts[_savedChatTile.id]?.hasReply ?? false,
                    onTap: _openSavedChat,
                    onLongPress: () => _showChatHubActions(_savedChatTile),
                  ),
                ],
              ),
            ),
          if (_showArchiveRow)
            SliverToBoxAdapter(
              child: ChatHubArchiveRow(
                count: _archivedCount,
                unread: _archivedUnread,
                preview: _archivedPreview,
                onTap: () => unawaited(_openArchivedFromHub()),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = visible[index];
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
                      draftText: _drafts[chat.id]?.hubPreview,
                      draftHasReply: _drafts[chat.id]?.hasReply ?? false,
                      typingLabel: _typingLabelFor(chat.id),
                      onTap: () async {
                        await context.push(
                          ChatThreadRoute.pathFor(chat),
                          extra: chat,
                        );
                        if (mounted) {
                          unawaited(_refreshDrafts());
                          _load();
                        }
                      },
                      onLongPress: () => _showChatHubActions(chat),
                    ),
                  );
                }
                final channelEntry = entry as ChannelInboxEntry;
                return ChannelInboxSlidable(
                  key: ValueKey('channel_${channelEntry.channel.id}'),
                  channelId: channelEntry.channel.id,
                  muted: channelEntry.muted,
                  onArchive: () => _archiveChannelFromHub(channelEntry.channel),
                  onToggleMute: () =>
                      _toggleChannelMuteFromHub(channelEntry.channel),
                  onLeave: () => _leaveChannelFromHub(channelEntry.channel),
                  child: ChannelInboxTile(
                    channel: channelEntry.channel,
                    muted: channelEntry.muted,
                    isFavorite: channelEntry.isFavorite,
                    onSortAtChanged: (dt) =>
                        _onChannelSortAtChanged(channelEntry, dt),
                    onTap: () => _openChannel(channelEntry.channel.id),
                    onMarkedSeen: () {
                      ref.read(shellChatBadgeRefreshProvider.notifier).state++;
                    },
                    onLongPress: () => _showChannelHubActions(
                      channelEntry.channel,
                      isFavorite: channelEntry.isFavorite,
                      notificationsEnabled: channelEntry.notificationsEnabled,
                    ),
                  ),
                );
              },
              childCount: visible.length,
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
