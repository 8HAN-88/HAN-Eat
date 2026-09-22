import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

class ChatGroupModerationLogScreen extends StatefulWidget {
  const ChatGroupModerationLogScreen({
    super.key,
    this.conversation,
    this.conversationId,
  });

  final ChatConversation? conversation;
  final int? conversationId;

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
  bool _missing = false;
  Object? _error;
  List<ChatGroupModerationLogItem> _items = [];
  ChatConversation? _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    if (_conversation == null && widget.conversationId != null) {
      unawaited(_hydrate());
    } else if (_conversation != null) {
      unawaited(_load());
    } else {
      _loading = false;
      _missing = true;
    }
  }

  Future<void> _hydrate() async {
    final id = widget.conversationId;
    if (id == null) {
      setState(() {
        _missing = true;
        _loading = false;
      });
      return;
    }
    try {
      final conv = await ChatService.getConversation(id);
      if (!mounted) return;
      setState(() => _conversation = conv);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _missing = true;
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    final conversation = _conversation;
    if (conversation == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.listGroupModerationLog(
        conversation.id,
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
    if (_missing && _conversation == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('История модерации'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Назад',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(ChatsRoute.path);
              }
            },
          ),
        ),
        body: AppEmptyState(
          icon: Icons.shield_outlined,
          title: 'Чат не найден',
          subtitle: 'Ссылка устарела или диалог недоступен',
          action: FilledButton(
            onPressed: () => context.go(ChatsRoute.path),
            child: const Text('К чатам'),
          ),
        ),
      );
    }
    final title = _conversation?.displayTitle ?? 'группа';
    return Scaffold(
      appBar: AppBar(
        title: const Text('История модерации'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final cid = widget.conversationId ?? widget.conversation?.id;
              context.go(
                cid != null
                    ? ChatThreadRoute.pathForId(cid)
                    : ChatsRoute.path,
              );
            }
          },
        ),
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
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Для "$title" пока нет записей',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            if (_selectedFilter != 'all')
                              FilledButton(
                                onPressed: () {
                                  setState(() => _selectedFilter = 'all');
                                  _load();
                                },
                                child: const Text('Все события'),
                              )
                            else
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Обновить'),
                              ),
                          ],
                        ),
                      ),
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
