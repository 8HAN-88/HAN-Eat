import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/channel_service.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import '../../../core/phone/phone_hash.dart';
import '../../../services/app_invite_service.dart';
import '../../../services/phone_contacts_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/chat_inbox_skeleton.dart';
import '../../channels/application/channels_list_refresh_provider.dart';
import '../application/chat_realtime_signals.dart';
import '../application/chats_hub_search.dart';
import '../application/chats_hub_refresh_provider.dart';
import '../../navigation/application/shell_tab_visibility.dart';
import '../../navigation/application/shell_chat_badge_refresh_provider.dart';
import '../../../services/channel_sheet_prefs.dart';
import 'chat_archived_screen.dart';
import 'chat_create_group_screen.dart';
import 'chat_people_search_screen.dart';

/// Раздел «Чаты»: диалоги, каналы и контакты в одном месте (как в Telegram).
class ChatsHubScreen extends ConsumerStatefulWidget {
  const ChatsHubScreen({super.key});

  @override
  ConsumerState<ChatsHubScreen> createState() => _ChatsHubScreenState();
}

class _ChatsHubScreenState extends ConsumerState<ChatsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    chatsHubSearchOpenRequest.addListener(_onExternalSearchOpen);
  }

  @override
  void dispose() {
    chatsHubSearchOpenRequest.removeListener(_onExternalSearchOpen);
    _searchController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onExternalSearchOpen() {
    if (!mounted || _searchOpen) return;
    setState(() => _searchOpen = true);
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _openPeopleSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChatPeopleSearchScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCreateGroup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChatCreateGroupScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openArchived() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChatArchivedScreen()),
    );
    if (mounted) setState(() {});
  }

  void _showNewChatMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Новое сообщение'),
              onTap: () {
                Navigator.pop(ctx);
                _openPeopleSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Новая группа'),
              onTap: () {
                Navigator.pop(ctx);
                _openCreateGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createChannel() async {
    final channelId = await context.push<int?>(CreateChannelRoute.path);
    if (!mounted) return;
    if (channelId != null) {
      ref.read(channelsMainListRefreshProvider.notifier).state++;
      context.push(ChannelDetailRoute.pathFor(channelId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Чаты')),
        body: const AppEmptyState(
          icon: Icons.login_rounded,
          title: 'Войдите в аккаунт',
          subtitle: 'Чтобы переписываться и читать каналы.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_searchOpen ? 104 : 48),
          child: Column(
            children: [
              if (_searchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Чаты, каналы, контакты',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _toggleSearch,
                      ),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Все'),
                  Tab(text: 'Контакты'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Архив чатов и каналов',
            onPressed: _openArchived,
          ),
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Каталог каналов',
            onPressed: () => context.push(ChannelsManagementRoute.path),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Найти людей',
            onPressed: _openPeopleSearch,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Создать канал',
            onPressed: _createChannel,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AllInboxTab(
            searchQuery: _searchQuery,
            onSwitchToContacts: () => _tabs.animateTo(_ContactsTab.contactsTabIndex),
          ),
          _ContactsTab(tabController: _tabs, searchQuery: _searchQuery),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: fabExtraBottomPadding(context)),
        child: FloatingActionButton(
          onPressed: _showNewChatMenu,
          tooltip: 'Новый чат',
          child: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}

class _AllInboxTab extends ConsumerStatefulWidget {
  const _AllInboxTab({
    required this.searchQuery,
    required this.onSwitchToContacts,
  });

  final String searchQuery;
  final VoidCallback onSwitchToContacts;

  @override
  ConsumerState<_AllInboxTab> createState() => _AllInboxTabState();
}

class _AllInboxTabState extends ConsumerState<_AllInboxTab>
    with WidgetsBindingObserver {
  final _entries = <_InboxEntry>[];
  List<Channel> _recommended = [];
  bool _loading = false;
  bool _started = false;
  Object? _error;
  Object? _chatsPartialError;
  int _loadSeq = 0;
  int? _hubActionChatId;
  Timer? _pollTimer;
  StreamSubscription<void>? _signalSub;
  bool _appPaused = false;
  _InboxFilter _inboxFilter = _InboxFilter.all;
  ChatConversation? _savedChat;
  bool _openingSaved = false;

  bool get _showSavedPinned =>
      widget.searchQuery.trim().isEmpty &&
      _inboxFilter != _InboxFilter.channels;

  ChatConversation get _savedChatTile => _savedChat ??
      ChatConversation(
        id: 0,
        type: 'saved',
        updatedAt: DateTime.now(),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShellTabVisibility.activeIndex.addListener(_onShellTabChanged);
    _signalSub = ChatRealtimeSignals.instance.hubRefresh.listen((_) {
      if (mounted && _started && ShellTabVisibility.chatsActive && !_loading) {
        _load(silent: true);
      }
    });
    _maybeStartLoading();
  }

  void _onShellTabChanged() {
    _maybeStartLoading();
  }

  void _maybeStartLoading() {
    if (!ShellTabVisibility.chatsActive) return;
    if (_started) return;
    _started = true;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_appPaused && !_loading && ShellTabVisibility.chatsActive) {
        _load(silent: true);
      }
    });
    _load();
  }

  @override
  void dispose() {
    ShellTabVisibility.activeIndex.removeListener(_onShellTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _signalSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
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
      if (a is _ChatInboxEntry && b is _ChatInboxEntry) {
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
      final cached = await ChatCacheService.loadConversations();
      if (!mounted || seq != _loadSeq) return;
      if (cached != null && cached.isNotEmpty) {
        final cachedSaved = _extractSavedChat(cached);
        final cachedRest = _withoutSavedChat(cached, cachedSaved);
        setState(() {
          if (cachedSaved != null) _savedChat = cachedSaved;
          _entries
            ..clear()
            ..addAll(cachedRest.map(_ChatInboxEntry.new));
          _loading = false;
          _error = null;
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
    List<Channel> recommended = [];
    Object? channelsError;
    var favoriteIds = <int>{};
    var archivedChannelIds = <int>{};

    await Future.wait<void>([
      () async {
        try {
          chats = await ChatService.listConversations();
        } catch (e) {
          chatsError = e;
          debugPrint('Chats load failed: $e');
        }
      }(),
      () async {
        try {
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
          try {
            final rec = await ChannelService.listChannels(
              limit: 8,
              offset: 0,
              recommended: true,
              withLastPost: true,
            );
            final known = channels.map((c) => c.id).toSet();
            recommended = rec.items
                .where((c) =>
                    !known.contains(c.id) &&
                    !archivedChannelIds.contains(c.id))
                .toList();
          } catch (_) {}
        } catch (e) {
          channelsError = e;
          debugPrint('Channels load failed: $e');
        }
      }(),
    ]);

    if (!mounted || seq != _loadSeq) return;

    final resolvedSaved = _extractSavedChat(chats) ?? _savedChat;
    chats = _withoutSavedChat(chats, resolvedSaved);

    if (chats.isEmpty &&
        channels.isEmpty &&
        recommended.isEmpty &&
        resolvedSaved == null) {
      setState(() {
        _entries.clear();
        _recommended = [];
        _error = chatsError ?? channelsError;
        _chatsPartialError = null;
        _loading = false;
      });
      return;
    }

    final channelEntries = channels
        .map(
          (c) => _ChannelInboxEntry(
            channel: c,
            isFavorite: favoriteIds.contains(c.id),
          ),
        )
        .toList();
    channelEntries.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return b.sortAt.compareTo(a.sortAt);
    });

    final entries = <_InboxEntry>[
      ...chats.map(_ChatInboxEntry.new),
      ...channelEntries,
    ]..sort((a, b) {
        final aFav = a is _ChannelInboxEntry && a.isFavorite;
        final bFav = b is _ChannelInboxEntry && b.isFavorite;
        if (aFav != bFav) return aFav ? -1 : 1;
        if (a is _ChatInboxEntry && b is _ChatInboxEntry) {
          if (a.chat.pinned != b.chat.pinned) {
            return a.chat.pinned ? -1 : 1;
          }
          return b.sortAt.compareTo(a.sortAt);
        }
        if (a is _ChannelInboxEntry && b is _ChannelInboxEntry) {
          return b.sortAt.compareTo(a.sortAt);
        }
        return b.sortAt.compareTo(a.sortAt);
      });

    setState(() {
      if (resolvedSaved != null) _savedChat = resolvedSaved;
      _entries
        ..clear()
        ..addAll(entries);
      _recommended = recommended;
      _error = null;
      _chatsPartialError =
          chatsError != null && (channels.isNotEmpty || recommended.isNotEmpty)
              ? chatsError
              : null;
      _loading = false;
    });
  }

  void _onChannelSortAtChanged(_ChannelInboxEntry entry, DateTime sortAt) {
    if (!mounted) return;
    setState(() {
      entry.sortAt = sortAt;
      _sortEntries();
    });
  }

  List<_InboxEntry> get _filteredEntries {
    if (_inboxFilter == _InboxFilter.all) return _entries;
    return _entries.where((e) {
      if (e is _ChatInboxEntry && e.chat.isSaved) return false;
      switch (_inboxFilter) {
        case _InboxFilter.all:
          return true;
        case _InboxFilter.unread:
          if (e is _ChatInboxEntry) return e.chat.unreadCount > 0;
          if (e is _ChannelInboxEntry) {
            return e.channel.inboxUnreadPosts > 0;
          }
          return false;
        case _InboxFilter.groups:
          return e is _ChatInboxEntry && e.chat.isGroup;
        case _InboxFilter.channels:
          return e is _ChannelInboxEntry;
        case _InboxFilter.pinned:
          if (e is _ChatInboxEntry) return e.chat.pinned;
          if (e is _ChannelInboxEntry) return e.isFavorite;
          return false;
      }
    }).toList();
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

  List<_InboxEntry> get _visibleEntries {
    final base = _filteredEntries
        .where(
          (e) => !(e is _ChatInboxEntry && e.chat.isSaved),
        )
        .toList();
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((e) {
      if (e is _ChatInboxEntry) {
        final preview = e.chat.lastMessage?.content ?? '';
        return e.chat.displayTitle.toLowerCase().contains(q) ||
            preview.toLowerCase().contains(q);
      }
      if (e is _ChannelInboxEntry) {
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

  Widget _inboxFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('Все'),
            selected: _inboxFilter == _InboxFilter.all,
            onSelected: (_) => setState(() => _inboxFilter = _InboxFilter.all),
          ),
          FilterChip(
            label: const Text('Непрочитанные'),
            selected: _inboxFilter == _InboxFilter.unread,
            onSelected: (_) =>
                setState(() => _inboxFilter = _InboxFilter.unread),
          ),
          FilterChip(
            label: const Text('Группы'),
            selected: _inboxFilter == _InboxFilter.groups,
            onSelected: (_) =>
                setState(() => _inboxFilter = _InboxFilter.groups),
          ),
          FilterChip(
            label: const Text('Каналы'),
            selected: _inboxFilter == _InboxFilter.channels,
            onSelected: (_) =>
                setState(() => _inboxFilter = _InboxFilter.channels),
          ),
          FilterChip(
            label: const Text('Закреплённые'),
            selected: _inboxFilter == _InboxFilter.pinned,
            onSelected: (_) =>
                setState(() => _inboxFilter = _InboxFilter.pinned),
          ),
        ],
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
      if (q.isEmpty &&
          _inboxFilter != _InboxFilter.all &&
          _entries.isNotEmpty) {
        return AppEmptyState(
          icon: Icons.filter_list_off,
          title: 'Нет чатов',
          subtitle: switch (_inboxFilter) {
            _InboxFilter.unread => 'Непрочитанных диалогов и каналов нет.',
            _InboxFilter.groups => 'Групповых чатов пока нет.',
            _InboxFilter.channels => 'Подписок на каналы пока нет.',
            _InboxFilter.pinned => 'Закреплённых чатов и избранных каналов нет.',
            _InboxFilter.all => '',
          },
          action: FilledButton(
            onPressed: () => setState(() => _inboxFilter = _InboxFilter.all),
            child: const Text('Показать все'),
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
          if (widget.searchQuery.trim().isEmpty)
            SliverToBoxAdapter(child: _inboxFilterBar()),
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
                  _ChatTile(
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
                if (entry is _ChatInboxEntry) {
                  final chat = entry.chat;
                  return _SwipeableChatTile(
                    chat: chat,
                    onTap: () async {
                      await context.push(
                        ChatThreadRoute.pathFor(chat),
                        extra: chat,
                      );
                      if (mounted) _load();
                    },
                    onLongPress: () => _showChatHubActions(chat),
                    onArchive: () => _archiveChatFromHub(chat),
                  );
                }
                final channelEntry = entry as _ChannelInboxEntry;
                return _SwipeableChannelTile(
                  key: ValueKey('channel_${channelEntry.channel.id}'),
                  channel: channelEntry.channel,
                  entry: channelEntry,
                  onSortAtChanged: (dt) =>
                      _onChannelSortAtChanged(channelEntry, dt),
                  onTap: () => _openChannel(channelEntry.channel.id),
                  onLongPress: () =>
                      _showChannelHubActions(channelEntry.channel),
                  onMarkedSeen: () {
                    ref.read(shellChatBadgeRefreshProvider.notifier).state++;
                  },
                  onArchive: () =>
                      _archiveChannelFromHub(channelEntry.channel),
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
                    return _RecommendedChannelChip(
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

sealed class _InboxEntry {
  DateTime get sortAt;
}

enum _InboxFilter { all, unread, groups, channels, pinned }

class _ChatInboxEntry extends _InboxEntry {
  _ChatInboxEntry(this.chat);

  final ChatConversation chat;

  @override
  DateTime get sortAt => chat.updatedAt;
}

class _ChannelInboxEntry extends _InboxEntry {
  _ChannelInboxEntry({
    required this.channel,
    this.isFavorite = false,
  }) : sortAt = channel.lastPostAt ?? channel.createdAt;

  final Channel channel;
  final bool isFavorite;

  @override
  DateTime sortAt;
}

class _ChannelInboxTile extends StatefulWidget {
  const _ChannelInboxTile({
    super.key,
    required this.entry,
    required this.onSortAtChanged,
    required this.onTap,
    required this.onMarkedSeen,
    this.onLongPress,
  });

  final _ChannelInboxEntry entry;
  final ValueChanged<DateTime> onSortAtChanged;
  final VoidCallback onTap;
  final VoidCallback onMarkedSeen;
  final VoidCallback? onLongPress;

  @override
  State<_ChannelInboxTile> createState() => _ChannelInboxTileState();
}

class _ChannelInboxTileState extends State<_ChannelInboxTile> {
  String? _preview;
  DateTime? _lastPostAt;
  bool _loadingPost = false;
  late int _seenPostsCount;

  Channel get _channel => widget.entry.channel;

  int get _newPostsCount {
    final delta = _channel.postsCount - _seenPostsCount;
    return delta > 0 ? delta : 0;
  }

  @override
  void initState() {
    super.initState();
    _seenPostsCount = _channel.seenPostsCount ?? 0;
    _preview = _channel.lastPostPreview;
    _lastPostAt = _channel.lastPostAt;
    if (_lastPostAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSortAtChanged(_lastPostAt!);
      });
    } else {
      _loadLastPostFallback();
    }
  }

  @override
  void didUpdateWidget(covariant _ChannelInboxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.channel.id != widget.entry.channel.id) {
      _seenPostsCount = _channel.seenPostsCount ?? 0;
      _preview = _channel.lastPostPreview;
      _lastPostAt = _channel.lastPostAt;
    } else {
      final serverSeen = _channel.seenPostsCount;
      if (serverSeen != null && serverSeen > _seenPostsCount) {
        _seenPostsCount = serverSeen;
      }
    }
  }

  Future<void> _markAsSeen() async {
    final latestCount = _channel.postsCount;
    if (latestCount <= _seenPostsCount) return;
    setState(() => _seenPostsCount = latestCount);
    try {
      final seen = await ChannelService.markChannelInboxRead(_channel.id);
      if (!mounted) return;
      setState(() => _seenPostsCount = seen);
      widget.onMarkedSeen();
    } catch (_) {}
  }

  Future<void> _loadLastPostFallback() async {
    if (_loadingPost || !_channel.canLoadPostsPreview || _channel.postsCount == 0) {
      return;
    }
    setState(() => _loadingPost = true);
    try {
      final response = await ChannelService.getChannelPosts(
        channelId: _channel.id,
        limit: 1,
        offset: 0,
      );
      if (response.posts.isEmpty || !mounted) return;
      final post = response.posts.first;
      final createdAt = DateTime.tryParse(
        post['created_at']?.toString() ?? '',
      )?.toLocal();
      setState(() {
        _preview = _postPreview(post);
        _lastPostAt = createdAt;
      });
      if (createdAt != null) {
        widget.onSortAtChanged(createdAt);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPost = false);
    }
  }

  String _postPreview(Map<String, dynamic> post) {
    final title = (post['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;
    final description = (post['description'] as String?)?.trim();
    if (description != null && description.isNotEmpty) return description;
    final type = (post['type'] as String?)?.toLowerCase() ?? '';
    if (type == 'recipe') return 'Рецепт';
    if (type == 'reel' || type == 'video') return 'Видео';
    if (type == 'photo' || type == 'image') return 'Фото';
    return 'Новый пост';
  }

  String _subtitle() {
    if (_channel.postsCount > 0 && _loadingPost) return 'Загрузка…';
    if (_preview != null) return _preview!;
    final d = _channel.description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return 'Канал';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = _newPostsCount > 0;

    return ListTile(
      onTap: () async {
        await _markAsSeen();
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      leading: _ChannelAvatar(channel: _channel),
      title: Row(
        children: [
          Icon(Icons.campaign_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _subtitle(),
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
            _formatTime(_lastPostAt ?? _channel.createdAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: scheme.primary,
              child: Text(
                _newPostsCount > 9 ? '9+' : '$_newPostsCount',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactsTab extends StatefulWidget {
  const _ContactsTab({
    required this.tabController,
    required this.searchQuery,
  });

  static const contactsTabIndex = 1;

  final TabController tabController;
  final String searchQuery;

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab> {
  List<ChatContact> _items = [];
  List<PhoneBookContact> _phoneBook = [];
  bool _loading = false;
  bool _syncingPhone = false;
  bool _loadStarted = false;
  bool _phonePermissionDenied = false;
  Object? _error;
  Object? _phoneSyncError;
  int? _contactActionUserId;
  int _contactsLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onSubTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSubTabChanged());
  }

  void _onSubTabChanged() {
    if (!mounted || widget.tabController.indexIsChanging) return;
    if (_isContactsSubTabVisible && !_loadStarted) {
      _loadStarted = true;
      _loadAll();
      return;
    }
    setState(() {});
  }

  bool get _isContactsSubTabVisible =>
      widget.tabController.index == _ContactsTab.contactsTabIndex;

  String get _query => widget.searchQuery.trim().toLowerCase();

  List<PhoneBookContact> get _visiblePhoneBook {
    final q = _query;
    if (q.isEmpty) return _phoneBook;
    return _phoneBook.where((entry) {
      if (entry.displayName.toLowerCase().contains(q)) return true;
      if (entry.phoneE164.toLowerCase().contains(q)) return true;
      final matched = entry.matchedUser;
      if (matched == null) return false;
      return (matched.name?.toLowerCase().contains(q) ?? false) ||
          (matched.username?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  List<ChatContact> get _visibleItems {
    final q = _query;
    if (q.isEmpty) return _items;
    return _items.where((contact) {
      return contact.user.displayName.toLowerCase().contains(q) ||
          (contact.user.username?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onSubTabChanged);
    super.dispose();
  }

  Future<void> _loadAll() async {
    final seq = ++_contactsLoadSeq;
    setState(() {
      _loading = true;
      _syncingPhone = true;
      _error = null;
      _phoneSyncError = null;
      _phonePermissionDenied = false;
    });
    try {
      await Future.wait([
        _fetchContacts(),
        _fetchPhoneContacts(),
      ]);
    } finally {
      if (mounted && seq == _contactsLoadSeq) {
        setState(() {
          _loading = false;
          _syncingPhone = false;
        });
      }
    }
  }

  Future<void> _fetchContacts() async {
    try {
      final items = await ChatService.listContacts();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _fetchPhoneContacts() async {
    try {
      final result = await PhoneContactsService.syncFromDevice();
      if (!mounted) return;
      setState(() {
        _phoneBook = result.phoneBook;
        _phonePermissionDenied = false;
        _phoneSyncError = result.apiError;
      });
    } on PhoneContactsPermissionDenied {
      if (!mounted) return;
      setState(() {
        _phoneBook = [];
        _phonePermissionDenied = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _phoneSyncError = e);
    }
  }

  Future<void> _retryPhonePermission() async {
    setState(() {
      _syncingPhone = true;
      _phoneSyncError = null;
      _phonePermissionDenied = false;
    });
    await _fetchPhoneContacts();
    if (mounted) setState(() => _syncingPhone = false);
  }

  Future<void> _addPhoneContact({bool offerAccountLink = false}) async {
    final nameController = TextEditingController(
      text: AuthService.instance.currentUser?.name ?? '',
    );
    final phoneController = TextEditingController();
    var linkToAccount = offerAccountLink;
    final formKey = GlobalKey<FormState>();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Новый контакт'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Имя',
                      hintText: 'Иван Петров',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите имя';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Номер',
                      hintText: '+7 900 123-45-67',
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return 'Введите номер';
                      if (normalizePhoneE164(raw) == null) {
                        return 'Некорректный номер';
                      }
                      return null;
                    },
                  ),
                  if (offerAccountLink) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: linkToAccount,
                      onChanged: (value) {
                        setDialogState(() => linkToAccount = value ?? false);
                      },
                      title: const Text('Это мой номер в HAN Eat'),
                      subtitle: const Text(
                        'Друзья из телефона смогут вас найти',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      );
      if (saved != true || !mounted) return;

      final name = nameController.text.trim();
      final phone = phoneController.text.trim();

      await PhoneContactsService.addContactToDevice(
        displayName: name,
        phoneRaw: phone,
      );

      var linked = false;
      if (linkToAccount) {
        try {
          await AuthService.linkPhone(phone);
          linked = true;
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Контакт сохранён, но номер не привязан: ${userVisibleError(e)}',
              ),
            ),
          );
          await _fetchPhoneContacts();
          if (mounted) setState(() {});
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            linked
                ? 'Контакт сохранён в телефоне, номер привязан'
                : 'Контакт сохранён в телефоне',
          ),
        ),
      );
      await _fetchPhoneContacts();
      if (mounted) setState(() {});
    } on PhoneContactsPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Нужен доступ к контактам. '
            'Настройки → HAN Eat → Контакты → разрешить изменения.',
          ),
        ),
      );
    } on PhoneContactsInvalidInput catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _openChatWithUser(int userId) async {
    try {
      final conv = await ChatService.openDirectChat(userId);
      if (!context.mounted) return;
      await context.push(ChatThreadRoute.pathFor(conv), extra: conv);
      if (mounted) _fetchContacts();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addHanEatContact(int userId) async {
    if (_contactActionUserId != null) return;
    setState(() => _contactActionUserId = userId);
    try {
      await ChatService.addContact(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено в контакты')),
      );
      await _fetchContacts();
      await _fetchPhoneContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _contactActionUserId = null);
    }
  }

  Future<void> _removeHanEatContact(int userId, String name) async {
    if (_contactActionUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить контакт?'),
        content: Text('$name будет убран из списка «Мои контакты».'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _contactActionUserId = userId);
    try {
      await ChatService.removeContact(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Контакт удалён')),
      );
      await _fetchContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _contactActionUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isContactsSubTabVisible) {
      return const SizedBox.shrink();
    }
    if (_loading && _items.isEmpty && _phoneBook.isEmpty && !_phonePermissionDenied) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty && _phoneBook.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить контакты',
        subtitle: userVisibleError(_error!),
        action: FilledButton(onPressed: _loadAll, child: const Text('Повторить')),
      );
    }

    final user = AuthService.instance.currentUser;
    final showLinkPhone = user != null && !user.phoneLinked;
    final phoneBook = _visiblePhoneBook;
    final items = _visibleItems;
    final searching = _query.isNotEmpty;

    if (searching &&
        phoneBook.isEmpty &&
        items.isEmpty &&
        !_loading &&
        _error == null) {
      return ListView(
        padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
        children: const [
          SizedBox(height: 48),
          AppEmptyState(
            icon: Icons.search_off,
            title: 'Ничего не найдено',
            subtitle: 'Попробуйте другой запрос.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
        children: [
          if (showLinkPhone)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.phone_android_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                title: Text(
                  'Привяжите номер',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Найдём друзей из телефонной книги и покажем, кто уже в HAN Eat',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.85),
                  ),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => _addPhoneContact(offerAccountLink: true),
                  child: const Text('Привязать'),
                ),
              ),
            ),
          if (_syncingPhone && !_loading)
            const LinearProgressIndicator(minHeight: 2),
          if (_phonePermissionDenied)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Доступ к контактам'),
                subtitle: const Text(
                  'Разрешите доступ к телефонной книге — друзья и приглашения появятся автоматически. '
                  'Если диалог не показывается, откройте Настройки → HAN Eat → Контакты.',
                ),
                trailing: _syncingPhone
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _retryPhonePermission,
                        child: const Text('Разрешить'),
                      ),
              ),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Добавить контакт'),
              subtitle: Text(
                showLinkPhone
                    ? 'Имя и номер сохранятся в телефонной книге'
                    : 'Сохранить в телефонной книге',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _addPhoneContact(offerAccountLink: showLinkPhone),
            ),
          ),
          if (_phoneSyncError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: MaterialBanner(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                content: Text(
                  'Не удалось проверить, кто уже в HAN Eat: '
                  '${userVisibleError(_phoneSyncError!)}. '
                  'Контакты из телефона показаны ниже.',
                ),
                leading: const Icon(Icons.info_outline),
                actions: [
                  TextButton(
                    onPressed: _retryPhonePermission,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          if (phoneBook.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Телефонная книга (${phoneBook.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...phoneBook.map((entry) {
              final matched = entry.matchedUser;
              if (matched != null) {
                return ListTile(
                  leading: _UserAvatar(user: matched.brief),
                  title: Text(entry.displayName),
                  subtitle: Text(
                    matched.name ?? '@${matched.username ?? matched.id}',
                  ),
                  trailing: matched.isContact
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : TextButton(
                          onPressed: _contactActionUserId == matched.id
                              ? null
                              : () => _addHanEatContact(matched.id),
                          child: const Text('В контакты'),
                        ),
                  onTap: () => _openChatWithUser(matched.id),
                );
              }
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Text(entry.displayName),
                subtitle: Text(entry.phoneE164),
                trailing: FilledButton.tonal(
                  onPressed: () => AppInviteService.inviteContact(
                    context,
                    displayName: entry.displayName,
                    phoneE164: entry.phoneE164,
                  ),
                  child: const Text('Пригласить'),
                ),
              );
            }),
            const Divider(height: 24),
          ],
          if (items.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Мои контакты',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...items.map((contact) {
              return Column(
                children: [
                  ListTile(
                    leading: _UserAvatar(user: contact.user),
                    title: Text(contact.user.displayName),
                    subtitle: contact.user.username != null
                        ? Text('@${contact.user.username}')
                        : null,
                    trailing: PopupMenuButton<String>(
                      enabled: _contactActionUserId == null,
                      onSelected: (value) {
                        switch (value) {
                          case 'chat':
                            _openChatWithUser(contact.user.id);
                          case 'remove':
                            _removeHanEatContact(
                              contact.user.id,
                              contact.user.displayName,
                            );
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'chat',
                          child: Text('Написать'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Удалить из контактов'),
                        ),
                      ],
                    ),
                    onTap: () => _openChatWithUser(contact.user.id),
                  ),
                  const Divider(height: 1, indent: 72),
                ],
              );
            }),
          ],
          if (items.isEmpty &&
              phoneBook.isEmpty &&
              _error == null &&
              !_phonePermissionDenied &&
              !_loading &&
              !searching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: AppEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Пока пусто',
                subtitle:
                    'В телефонной книге нет номеров с кодом страны или добавьте людей через поиск.',
              ),
            ),
        ],
      ),
    );
  }
}

class _SwipeableChannelTile extends StatelessWidget {
  const _SwipeableChannelTile({
    super.key,
    required this.channel,
    required this.entry,
    required this.onSortAtChanged,
    required this.onTap,
    required this.onLongPress,
    required this.onMarkedSeen,
    required this.onArchive,
  });

  final Channel channel;
  final _ChannelInboxEntry entry;
  final ValueChanged<DateTime> onSortAtChanged;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMarkedSeen;
  final Future<void> Function() onArchive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = _ChannelInboxTile(
      entry: entry,
      onSortAtChanged: onSortAtChanged,
      onTap: onTap,
      onMarkedSeen: onMarkedSeen,
      onLongPress: onLongPress,
    );
    return Dismissible(
      key: ValueKey('channel_swipe_${channel.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.secondaryContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.archive_outlined, color: scheme.onSecondaryContainer),
      ),
      confirmDismiss: (_) async {
        await onArchive();
        return false;
      },
      child: tile,
    );
  }
}

class _SwipeableChatTile extends StatelessWidget {
  const _SwipeableChatTile({
    required this.chat,
    required this.onTap,
    required this.onLongPress,
    required this.onArchive,
  });

  final ChatConversation chat;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function() onArchive;

  @override
  Widget build(BuildContext context) {
    final tile = _ChatTile(
      chat: chat,
      onTap: onTap,
      onLongPress: onLongPress,
    );
    if (chat.isSaved) return tile;

    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('chat_swipe_${chat.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.secondaryContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.archive_outlined, color: scheme.onSecondaryContainer),
      ),
      confirmDismiss: (_) async {
        await onArchive();
        return false;
      },
      child: tile,
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.onTap,
    this.onLongPress,
  });

  final ChatConversation chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _preview(ChatMessage? msg) {
    if (msg == null) {
      return chat.isSaved ? 'Сохраняйте сообщения и заметки' : 'Нет сообщений';
    }
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'image') return '📷 Фото';
    if (msg.type == 'video') return '🎬 Видео';
    if (msg.type == 'file') {
      final name = msg.content.trim();
      return name.isEmpty ? '📎 Файл' : '📎 $name';
    }
    if (chat.isGroup && (msg.senderName?.isNotEmpty ?? false)) {
      return '${msg.senderName}: ${msg.content}';
    }
    return msg.content;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = chat.lastMessage;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: chat.isSaved
          ? CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.bookmark_rounded,
                color: scheme.onPrimaryContainer,
              ),
            )
          : chat.isGroup
              ? _GroupAvatar(members: chat.membersPreview)
              : _UserAvatar(
                  user: chat.peer ??
                      const ChatUserBrief(id: 0, name: 'Чат'),
                ),
      title: Row(
        children: [
          if (chat.pinned) ...[
            Icon(Icons.push_pin, size: 14, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          if (chat.muted) ...[
            Icon(Icons.notifications_off_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight:
                    chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _preview(last),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chat.unreadCount > 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(chat.updatedAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (chat.unreadCount > 0) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: scheme.primary,
              child: Text(
                chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecommendedChannelChip extends StatelessWidget {
  const _RecommendedChannelChip({
    required this.channel,
    required this.onTap,
  });

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelAvatar(channel: channel),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.members});

  final List<ChatUserBrief> members;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (members.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.groups_rounded, color: scheme.onPrimaryContainer),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        members.first.displayName.characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final ChatUserBrief user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final resolved =
        url != null && url.isNotEmpty ? ServerConfig.resolveMediaUrl(url) : null;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage:
              resolved != null ? CachedNetworkImageProvider(resolved) : null,
          child: resolved == null
              ? Text(
                  _avatarLetter(user.displayName),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : null,
        ),
        if (user.isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final url = channel.avatarUrl;
    return CircleAvatar(
      radius: 24,
      backgroundImage:
          url != null ? CachedNetworkImageProvider(url) : null,
      child: url == null
          ? Text(
              _avatarLetter(channel.name),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : null,
    );
  }
}

String _avatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inDays == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (now.difference(local).inDays < 7) {
    const days = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    return days[local.weekday - 1];
  }
  return '${local.day}.${local.month}';
}
