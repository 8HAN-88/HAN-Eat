import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/presence_format.dart';

class ChatGroupInfoScreen extends StatefulWidget {
  const ChatGroupInfoScreen({
    super.key,
    required this.conversation,
    this.onConversationChanged,
    this.onLeftGroup,
  });

  final ChatConversation conversation;
  final ValueChanged<ChatConversation>? onConversationChanged;
  final VoidCallback? onLeftGroup;

  @override
  State<ChatGroupInfoScreen> createState() => _ChatGroupInfoScreenState();
}

class _ChatGroupInfoScreenState extends State<ChatGroupInfoScreen> {
  late ChatConversation _conversation;
  List<ChatUserBrief> _members = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  int? get _myId => AuthService.instance.currentUser?.id;

  bool get _isCreator =>
      _myId != null && _conversation.createdByUserId == _myId;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conv = await ChatService.getConversation(_conversation.id);
      final members = await ChatService.listMembers(_conversation.id);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _members = members;
        _loading = false;
      });
      widget.onConversationChanged?.call(conv);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: _conversation.displayTitle);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final conv = await ChatService.updateGroupTitle(
        conversationId: _conversation.id,
        title: next,
      );
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _busy = false;
      });
      widget.onConversationChanged?.call(conv);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleMute() async {
    final next = !_conversation.muted;
    setState(() => _busy = true);
    try {
      await ChatService.setMuted(
        conversationId: _conversation.id,
        muted: next,
      );
      if (!mounted) return;
      final updated = _conversation.copyWith(muted: next);
      setState(() {
        _conversation = updated;
        _busy = false;
      });
      widget.onConversationChanged?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addMembers() async {
    List<ChatContact> contacts;
    try {
      contacts = await ChatService.listContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      return;
    }
    final memberIds = _members.map((m) => m.id).toSet();
    final candidates = contacts
        .map((c) => c.user)
        .where((u) => !memberIds.contains(u.id))
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет контактов для добавления')),
      );
      return;
    }
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final selected = <int>{};
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Добавить участников')),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final user = candidates[index];
                        final checked = selected.contains(user.id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setModalState(() {
                              if (v == true) {
                                selected.add(user.id);
                              } else {
                                selected.remove(user.id);
                              }
                            });
                          },
                          title: Text(user.displayName),
                          secondary: CircleAvatar(
                            child: Text(
                              user.displayName.characters.first.toUpperCase(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, selected.toList()),
                      child: const Text('Добавить'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChatService.addGroupMembers(
        conversationId: _conversation.id,
        userIds: picked,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено: ${picked.length}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _removeMember(ChatUserBrief member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Удалить ${member.displayName} из группы?'),
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
    setState(() => _busy = true);
    try {
      await ChatService.removeGroupMember(
        conversationId: _conversation.id,
        userId: member.id,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content: const Text('Вы больше не будете получать сообщения в этом чате.'),
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
    setState(() => _busy = true);
    try {
      await ChatService.leaveGroup(conversationId: _conversation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onLeftGroup?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('О группе'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : Stack(
                  children: [
                    ListView(
                      children: [
                        const SizedBox(height: 16),
                        CircleAvatar(
                          radius: 40,
                          child: Text(
                            _conversation.displayTitle.characters.first
                                .toUpperCase(),
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _conversation.displayTitle,
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Center(
                          child: Text(
                            '${_members.length} участников',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: _busy ? null : _renameGroup,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Переименовать'),
                          ),
                        ),
                        SwitchListTile(
                          secondary: Icon(
                            _conversation.muted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_outlined,
                          ),
                          title: const Text('Без звука'),
                          subtitle: const Text('Не присылать push-уведомления'),
                          value: _conversation.muted,
                          onChanged: _busy ? null : (_) => _toggleMute(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_add_outlined),
                          title: const Text('Добавить участников'),
                          onTap: _busy ? null : _addMembers,
                        ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Участники',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        ..._members.map((member) {
                          final isMe = member.id == _myId;
                          final canRemove = _isCreator &&
                              !isMe &&
                              member.id != _conversation.createdByUserId;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                member.displayName.characters.first
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(
                              isMe
                                  ? '${member.displayName} (вы)'
                                  : member.displayName,
                            ),
                            subtitle: Text(
                              formatLastSeen(member.lastSeenAt),
                            ),
                            trailing: canRemove
                                ? IconButton(
                                    tooltip: 'Удалить',
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: _busy
                                        ? null
                                        : () => _removeMember(member),
                                  )
                                : null,
                          );
                        }),
                        const SizedBox(height: 80),
                      ],
                    ),
                    if (_busy)
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _leaveGroup,
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти из группы'),
                ),
              ),
            ),
    );
  }
}
