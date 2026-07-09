import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';

class ChatGroupModerationLogScreen extends StatefulWidget {
  const ChatGroupModerationLogScreen({
    super.key,
    required this.conversation,
  });

  final ChatConversation conversation;

  @override
  State<ChatGroupModerationLogScreen> createState() =>
      _ChatGroupModerationLogScreenState();
}

class _ChatGroupModerationLogScreenState
    extends State<ChatGroupModerationLogScreen> {
  static const _filters = <(String key, String label)>[
    ('all', 'Все'),
    ('joins', 'Заявки'),
    ('bans', 'Баны'),
    ('roles', 'Роли'),
    ('restrictions', 'Ограничения'),
    ('settings', 'Настройки'),
  ];

  String _selectedFilter = 'all';
  bool _loading = true;
  Object? _error;
  List<ChatGroupModerationLogItem> _items = [];

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
      final items = await ChatService.listGroupModerationLog(
        widget.conversation.id,
        action: _selectedFilter,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation.displayTitle;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История модерации'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: _filters.map((f) {
                final selected = _selectedFilter == f.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: selected,
                    onSelected: (_) {
                      if (_selectedFilter == f.$1) return;
                      setState(() => _selectedFilter = f.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(userVisibleError(_error!)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text('Для "$title" пока нет записей'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final actor = item.actor?.displayName ?? 'Система';
                          final ts = DateFormat(
                            'dd.MM.yyyy HH:mm',
                          ).format(item.createdAt.toLocal());
                          return ListTile(
                            leading: const Icon(Icons.shield_outlined),
                            title: Text(item.text),
                            subtitle: Text('$actor • $ts'),
                          );
                        },
                      ),
                    ),
    );
  }
}
