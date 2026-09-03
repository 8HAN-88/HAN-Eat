import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../application/chat_thread_prefetch.dart';
import '../application/chats_hub_refresh_provider.dart';
import 'widgets/chats_hub_contacts_tab.dart';

class ChatCreateGroupScreen extends StatefulWidget {
  const ChatCreateGroupScreen({super.key});

  @override
  State<ChatCreateGroupScreen> createState() => _ChatCreateGroupScreenState();
}

class _ChatCreateGroupScreenState extends State<ChatCreateGroupScreen> {
  final _title = TextEditingController();
  final _selected = <int, ChatUserBrief>{};
  List<ChatContact> _contacts = [];
  bool _loading = true;
  bool _creating = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.listContacts();
      if (!mounted) return;
      setState(() {
        _contacts = items;
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

  void _toggle(ChatUserBrief user) {
    setState(() {
      if (_selected.containsKey(user.id)) {
        _selected.remove(user.id);
      } else {
        _selected[user.id] = user;
      }
    });
  }

  Future<void> _create() async {
    final name = _title.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название группы')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одного участника')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final conv = await ChatService.createGroupChat(
        title: name,
        memberIds: _selected.keys.toList(),
      );
      if (!mounted) return;
      unawaited(ChatThreadPrefetch.warm(conv.id));
      context.pushReplacement(
        ChatThreadRoute.pathFor(conv),
        extra: conv,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_create()),
          ),
        ),
      );
    }
  }

  void _openContactsHub() {
    requestChatsHubTab(ChatsHubContactsTab.contactsTabIndex);
    context.go(ChatsRoute.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая группа'),
        actions: [
          TextButton(
            onPressed: _creating || _selected.isEmpty ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название группы',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final user = _selected.values.elementAt(i);
                  return InputChip(
                    label: Text(user.displayName),
                    onDeleted: () => _toggle(user),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? AppEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Не удалось загрузить контакты',
                        subtitle: userVisibleError(_error!),
                        action: FilledButton(
                          onPressed: _loadContacts,
                          child: const Text('Повторить'),
                        ),
                      )
                    : _contacts.isEmpty
                        ? AppEmptyState(
                            icon: Icons.group_add_outlined,
                            title: 'Нет контактов',
                            subtitle:
                                'Добавьте людей в контакты, чтобы собрать группу',
                            action: FilledButton(
                              onPressed: _openContactsHub,
                              child: const Text('К контактам'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              final user = contact.user;
                              final checked = _selected.containsKey(user.id);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (_) => _toggle(user),
                                title: Text(user.displayName),
                                secondary: CircleAvatar(
                                  child: Text(
                                    _avatarLetter(user.displayName),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

String _avatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}
