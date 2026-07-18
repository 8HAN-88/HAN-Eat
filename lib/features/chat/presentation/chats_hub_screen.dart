import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_bootstrap_state.dart';
import '../../../app/app_router.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/web/boot_ready_signal.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/telegram_ui.dart';
import '../../channels/application/channels_list_refresh_provider.dart';
import 'chat_archived_screen.dart';
import 'chat_create_group_screen.dart';
import 'chat_people_search_screen.dart';
import 'widgets/chats_hub_all_inbox_tab.dart';
import 'widgets/chats_hub_contacts_tab.dart';

/// Раздел «Чаты»: диалоги, каналы и контакты в одном месте (как в Telegram).
class ChatsHubScreen extends ConsumerStatefulWidget {
  const ChatsHubScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

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
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _lastTabIndex = _tabs.index;
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppBootstrapState.primaryUiReady.value = true;
      notifyPrimaryUiReady();
    });
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
    showTelegramActionSheet<void>(
      context: context,
      title: 'Новый',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Новое сообщение',
          onTap: _openPeopleSearch,
        ),
        TelegramActionSheetAction(
          icon: Icons.group_add_outlined,
          title: 'Новая группа',
          onTap: _openCreateGroup,
        ),
        TelegramActionSheetAction(
          icon: Icons.add_circle_outline,
          title: 'Создать канал',
          onTap: _createChannel,
        ),
      ],
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
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _ChatsNeoHeader(
              controller: _tabs,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: (value) => setState(() => _searchQuery = value),
              onClearSearch: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              onCreate: _showNewChatMenu,
              onMore: _openArchived,
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
      ),
    );
  }
}

class _ChatsNeoHeader extends StatelessWidget {
  const _ChatsNeoHeader({
    required this.controller,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCreate,
    required this.onMore,
  });

  final TabController controller;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCreate;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Сообщения',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                  ),
                ),
                NeoCircleAction(
                  icon: Icons.add_rounded,
                  tooltip: 'Новый чат',
                  onPressed: onCreate,
                ),
                const SizedBox(width: 8),
                NeoCircleAction(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'Архив',
                  onPressed: onMore,
                ),
              ],
            ),
            const SizedBox(height: 22),
            NeoUnderlineTabs(
              controller: controller,
              padding: EdgeInsets.zero,
              tabs: const [
                Tab(text: 'Чаты и каналы'),
                Tab(text: 'Контакты'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: scheme.surfaceContainer.withValues(alpha: 0.7),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.46),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.46),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
