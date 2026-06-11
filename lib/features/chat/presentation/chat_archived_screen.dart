import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_sheet_prefs.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final isEmpty = _chats.isEmpty && _channels.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
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
                      onRefresh: _load,
                      child: ListView(
                        children: [
                          if (_chats.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                'Чаты',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            ..._chats.map((chat) => _ArchivedChatTile(
                                  chat: chat,
                                  onUnarchive: () => _unarchiveChat(chat),
                                )),
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
                            ..._channels.map((channel) => _ArchivedChannelTile(
                                  channel: channel,
                                  onUnarchive: () => _unarchiveChannel(channel),
                                  onOpen: () async {
                                    await context.push(
                                      ChannelDetailRoute.pathFor(channel.id),
                                    );
                                    if (mounted) _load();
                                  },
                                )),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }
}

class _ArchivedChatTile extends StatelessWidget {
  const _ArchivedChatTile({
    required this.chat,
    required this.onUnarchive,
  });

  final ChatConversation chat;
  final VoidCallback onUnarchive;

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              chat.isSaved
                  ? Icons.bookmark_rounded
                  : chat.isGroup
                      ? Icons.groups_rounded
                      : Icons.person_rounded,
            ),
            title: Text(chat.displayTitle),
            subtitle: Text(
              chat.isSaved
                  ? 'Избранное'
                  : chat.isGroup
                      ? '${chat.memberCount} участников'
                      : 'Личный чат',
            ),
            onTap: () async {
              await context.push(
                ChatThreadRoute.pathFor(chat),
                extra: chat,
              );
            },
          ),
          const Divider(height: 1, indent: 72),
        ],
      ),
    );
  }
}

class _ArchivedChannelTile extends StatelessWidget {
  const _ArchivedChannelTile({
    required this.channel,
    required this.onUnarchive,
    required this.onOpen,
  });

  final Channel channel;
  final VoidCallback onUnarchive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: Text(channel.name),
            subtitle: const Text('Канал'),
            onTap: onOpen,
          ),
          const Divider(height: 1, indent: 72),
        ],
      ),
    );
  }
}
