import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../services/auth_service.dart';
import '../../channels/application/channels_list_refresh_provider.dart';
import '../application/chats_hub_search.dart';
import 'chat_archived_screen.dart';
import 'chat_create_group_screen.dart';
import 'chat_people_search_screen.dart';
import 'widgets/chats_hub_all_inbox_tab.dart';
import 'widgets/chats_hub_contacts_tab.dart';

/// Раздел «Чаты»: диалоги, каналы и контакты в одном месте (как в Telegram).
class ChatsHubScreen extends ConsumerStatefulWidget {
  const ChatsHubScreen({super.key});

  @override
  ConsumerState<ChatsHubScreen> createState() => _ChatsHubScreenState();
}

class _ChatsHubScreenState extends ConsumerState<ChatsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _lastTabIndex = 0;
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    chatsHubSearchOpenRequest.addListener(_onExternalSearchOpen);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    AppHaptics.selection();
  }

  @override
  void dispose() {
    chatsHubSearchOpenRequest.removeListener(_onExternalSearchOpen);
    _tabs.removeListener(_onTabChanged);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (v) {
              if (v == 'people') _openPeopleSearch();
              if (v == 'channels') context.push(ChannelsManagementRoute.path);
              if (v == 'create_channel') _createChannel();
              if (v == 'archive') _openArchived();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'people',
                child: _hubMenuRow(
                  Icons.person_search_outlined,
                  'Найти людей',
                ),
              ),
              PopupMenuItem(
                value: 'channels',
                child: _hubMenuRow(
                  Icons.explore_outlined,
                  'Каталог каналов',
                ),
              ),
              PopupMenuItem(
                value: 'create_channel',
                child: _hubMenuRow(
                  Icons.add_circle_outline,
                  'Создать канал',
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'archive',
                child: _hubMenuRow(
                  Icons.archive_outlined,
                  'Архив',
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ChatsHubAllInboxTab(
            searchQuery: _searchQuery,
            onSwitchToContacts: () =>
                _tabs.animateTo(ChatsHubContactsTab.contactsTabIndex),
          ),
          ChatsHubContactsTab(
            tabController: _tabs,
            searchQuery: _searchQuery,
          ),
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

Widget _hubMenuRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}
