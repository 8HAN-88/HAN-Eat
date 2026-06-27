import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../channels/application/channels_list_refresh_provider.dart';
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
  final TextEditingController _searchController = TextEditingController();
  int _lastTabIndex = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    AppHaptics.selection();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
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
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Создать канал'),
              onTap: () {
                Navigator.pop(ctx);
                _createChannel();
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
    final scheme = Theme.of(context).colorScheme;

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Сообщения'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Чаты и каналы'),
              Tab(text: 'Контакты'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Создать канал',
              onPressed: _createChannel,
              icon: const Icon(Icons.add_circle_outline),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              onSelected: (v) {
                if (v == 'archive') _openArchived();
              },
              itemBuilder: (ctx) => [
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
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: scheme.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  ChatsHubAllInboxTab(
                    searchQuery: _searchQuery,
                    onSwitchToContacts: () =>
                        _tabs.animateTo(ChatsHubContactsTab.contactsTabIndex),
                  ),
                  ChatsHubContactsTab(
                    tabController: _tabs,
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: fabExtraBottomPadding(context)),
          child: FloatingActionButton.extended(
            onPressed: _showNewChatMenu,
            tooltip: 'Новый чат',
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              'Новый',
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
