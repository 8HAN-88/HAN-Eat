import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/presence_format.dart';
import 'chat_group_moderation_log_screen.dart';
import 'chat_media_gallery_screen.dart';

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
  static const List<int> _slowModePresets = [
    0,
    5,
    10,
    15,
    30,
    60,
    120,
    300,
    600
  ];
  static const List<int> _antiFloodPresets = [0, 3, 5, 10, 15, 20, 30, 60];

  late ChatConversation _conversation;
  List<ChatUserBrief> _members = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  int? get _myId => AuthService.instance.currentUser?.id;

  bool get _isCreator =>
      _myId != null && _conversation.createdByUserId == _myId;

  bool get _amIAdmin => _conversation.amIGroupAdmin || _isCreator;
  bool get _canManageMembers => _conversation.amICanManageMembers || _isCreator;
  bool get _canManagePostingPermissions =>
      _conversation.amICanManagePostingPermissions || _isCreator;

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

  Future<void> _toggleOnlyAdminsCanPost() async {
    if (!_canManagePostingPermissions) return;
    final next = !_conversation.onlyAdminsCanPost;
    setState(() => _busy = true);
    try {
      final conv = await ChatService.setGroupOnlyAdminsCanPost(
        conversationId: _conversation.id,
        onlyAdminsCanPost: next,
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

  Future<void> _toggleJoinByRequestEnabled() async {
    if (!_canManageMembers) return;
    final next = !_conversation.joinByRequestEnabled;
    setState(() => _busy = true);
    try {
      final conv = await ChatService.setGroupJoinByRequestEnabled(
        conversationId: _conversation.id,
        enabled: next,
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

  String _slowModeLabel(int value) {
    if (value <= 0) return 'Выключен';
    if (value < 60) return '$value сек';
    final minutes = value ~/ 60;
    return '$minutes мин';
  }

  Future<void> _configureSlowMode() async {
    if (!_canManagePostingPermissions) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('Slow mode'),
              subtitle:
                  Text('Интервал между сообщениями для обычных участников'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _slowModePresets
                  .map(
                    (seconds) => ChoiceChip(
                      label: Text(_slowModeLabel(seconds)),
                      selected: _conversation.slowModeSeconds == seconds,
                      onSelected: (_) => Navigator.pop(ctx, seconds),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || picked == _conversation.slowModeSeconds || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final conv = await ChatService.setGroupSlowModeSeconds(
        conversationId: _conversation.id,
        seconds: picked,
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

  Future<void> _configureAntiFloodLimit() async {
    if (!_canManagePostingPermissions) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.speed_outlined),
              title: Text('Антифлуд'),
              subtitle:
                  Text('Максимум сообщений в минуту для обычных участников'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _antiFloodPresets
                  .map(
                    (limit) => ChoiceChip(
                      label: Text(limit <= 0 ? 'Выключен' : '$limit / мин'),
                      selected:
                          _conversation.antiFloodMaxMessagesPerMinute == limit,
                      onSelected: (_) => Navigator.pop(ctx, limit),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null ||
        picked == _conversation.antiFloodMaxMessagesPerMinute ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final conv = await ChatService.setGroupAntiFloodLimit(
        conversationId: _conversation.id,
        maxMessagesPerMinute: picked,
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

  Future<void> _addMembers() async {
    if (!_canManageMembers) return;
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

  Future<void> _setMemberAdmin(ChatUserBrief member, bool isAdmin) async {
    if (!_isCreator || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChatService.setGroupMemberAdmin(
        conversationId: _conversation.id,
        userId: member.id,
        isAdmin: isAdmin,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdmin
                ? 'Пользователь назначен модератором'
                : 'Права модератора сняты',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _editMemberPermissions(ChatUserBrief member) async {
    if (!_isCreator || !member.isGroupAdmin || !mounted) return;
    bool canManageMembers = member.canManageMembers;
    bool canManagePostingPermissions = member.canManagePostingPermissions;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Права: ${member.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Управлять участниками'),
                subtitle: const Text('Добавлять и удалять участников'),
                value: canManageMembers,
                onChanged: (v) => setModalState(() => canManageMembers = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Управлять правом писать'),
                subtitle: const Text('Менять "Только админы могут писать"'),
                value: canManagePostingPermissions,
                onChanged: (v) => setModalState(
                  () => canManagePostingPermissions = v,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChatService.setGroupMemberPermissions(
        conversationId: _conversation.id,
        userId: member.id,
        canManageMembers: canManageMembers,
        canManagePostingPermissions: canManagePostingPermissions,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Права модератора обновлены')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _editMemberSendRestriction(ChatUserBrief member) async {
    if (!_canManageMembers || member.isGroupCreator || !mounted) return;
    bool sendRestricted = member.sendRestricted;
    bool withDeadline = member.sendRestrictedUntil != null;
    DateTime? until = member.sendRestrictedUntil?.toLocal();
    final reasonController =
        TextEditingController(text: member.sendRestrictionReason ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Ограничить: ${member.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Запретить отправку сообщений'),
                  value: sendRestricted,
                  onChanged: (v) => setModalState(() => sendRestricted = v),
                ),
                if (sendRestricted) ...[
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: withDeadline,
                    onChanged: (v) =>
                        setModalState(() => withDeadline = v ?? false),
                    title: const Text('Ограничение по времени'),
                  ),
                  if (withDeadline)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        until == null
                            ? 'Выбрать срок'
                            : 'До: ${until!.day.toString().padLeft(2, '0')}.${until!.month.toString().padLeft(2, '0')}.${until!.year} ${until!.hour.toString().padLeft(2, '0')}:${until!.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                          initialDate:
                              until ?? now.add(const Duration(days: 1)),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            until ?? now.add(const Duration(hours: 1)),
                          ),
                        );
                        if (time == null) return;
                        setModalState(() {
                          until = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                    ),
                  TextField(
                    controller: reasonController,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Причина (опционально)',
                      hintText: 'Например: флуд / спам',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (confirmed != true || !mounted) return;
    if (sendRestricted && withDeadline && until == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите срок ограничения')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ChatService.setGroupMemberSendRestriction(
        conversationId: _conversation.id,
        userId: member.id,
        sendRestricted: sendRestricted,
        sendRestrictedUntil: sendRestricted && withDeadline ? until : null,
        reason: sendRestricted ? reasonController.text : null,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sendRestricted
                ? 'Ограничение на отправку установлено'
                : 'Ограничение на отправку снято',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _banMember(ChatUserBrief member) async {
    if (!_canManageMembers || member.isGroupCreator || !mounted) return;
    final reasonController = TextEditingController();
    DateTime? until;
    bool withDeadline = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Забанить: ${member.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: withDeadline,
                  onChanged: (v) =>
                      setModalState(() => withDeadline = v ?? false),
                  title: const Text('Бан по времени'),
                ),
                if (withDeadline)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      until == null
                          ? 'Выбрать срок'
                          : 'До: ${until!.day.toString().padLeft(2, '0')}.${until!.month.toString().padLeft(2, '0')}.${until!.year} ${until!.hour.toString().padLeft(2, '0')}:${until!.minute.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.schedule_outlined),
                    onTap: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: now.add(const Duration(days: 1)),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time == null) return;
                      setModalState(() {
                        until = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                  ),
                TextField(
                  controller: reasonController,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Причина (опционально)',
                    hintText: 'Например: спам / токсичность',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Забанить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (withDeadline && until == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите срок бана')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ChatService.banGroupMember(
        conversationId: _conversation.id,
        userId: member.id,
        reason: reasonController.text,
        bannedUntil: withDeadline ? until : null,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Пользователь забанен и удален из группы')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _openBansSheet() async {
    if (!_canManageMembers || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<List<ChatGroupBanEntry>> load() =>
                ChatService.listGroupBans(_conversation.id);
            return FutureBuilder<List<ChatGroupBanEntry>>(
              future: load(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SafeArea(
                    child: SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                if (snap.hasError) {
                  return SafeArea(
                    child: SizedBox(
                      height: 260,
                      child: Center(
                        child: Text(userVisibleError(snap.error!)),
                      ),
                    ),
                  );
                }
                final items = snap.data ?? const <ChatGroupBanEntry>[];
                return SafeArea(
                  child: SizedBox(
                    height: 420,
                    child: items.isEmpty
                        ? const Center(child: Text('Бан-лист пуст'))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final row = items[index];
                              final until = row.bannedUntil;
                              return ListTile(
                                leading: const Icon(Icons.block_outlined),
                                title: Text(row.user.displayName),
                                subtitle: Text(
                                  [
                                    if (until == null)
                                      'Бессрочно'
                                    else
                                      'До ${until.toLocal().day.toString().padLeft(2, '0')}.${until.toLocal().month.toString().padLeft(2, '0')}.${until.toLocal().year}',
                                    if ((row.reason ?? '').trim().isNotEmpty)
                                      row.reason!.trim(),
                                  ].join(' • '),
                                ),
                                trailing: TextButton(
                                  onPressed: () async {
                                    try {
                                      await ChatService.unbanGroupMember(
                                        conversationId: _conversation.id,
                                        userId: row.user.id,
                                      );
                                      setModalState(() {});
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Пользователь разбанен')),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(userVisibleError(e)),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Разбанить'),
                                ),
                              );
                            },
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openInviteLinkSheet() async {
    if (!_canManageMembers || !mounted) return;
    List<ChatGroupInviteLink> links = [];
    bool loading = false;
    String? err;
    try {
      links = await ChatService.listGroupInviteLinks(
        _conversation.id,
        includeRevoked: true,
      );
    } catch (e) {
      err = userVisibleError(e);
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> reload() async {
            setModalState(() {
              loading = true;
              err = null;
            });
            try {
              links = await ChatService.listGroupInviteLinks(
                _conversation.id,
                includeRevoked: true,
              );
              setModalState(() => loading = false);
            } catch (e) {
              setModalState(() {
                loading = false;
                err = userVisibleError(e);
              });
            }
          }

          Future<void> copy(ChatGroupInviteLink link) async {
            await Clipboard.setData(ClipboardData(text: link.inviteLink));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ссылка скопирована')),
              );
            }
          }

          Future<void> rotateMain() async {
            setModalState(() => loading = true);
            try {
              await ChatService.rotateGroupInviteLink(_conversation.id);
              await reload();
            } catch (e) {
              setModalState(() {
                loading = false;
                err = userVisibleError(e);
              });
            }
          }

          Future<void> revoke(ChatGroupInviteLink link) async {
            setModalState(() => loading = true);
            try {
              await ChatService.revokeGroupInviteLink(
                conversationId: _conversation.id,
                inviteLinkId: link.id,
              );
              await reload();
            } catch (e) {
              setModalState(() {
                loading = false;
                err = userVisibleError(e);
              });
            }
          }

          Future<void> createLink() async {
            final usesCtrl = TextEditingController();
            bool withExpiry = false;
            DateTime? expiry;
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                  title: const Text('Новая ссылка-приглашение'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: withExpiry,
                        onChanged: (v) =>
                            setDialogState(() => withExpiry = v ?? false),
                        title: const Text('Указать срок действия'),
                      ),
                      if (withExpiry)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            expiry == null
                                ? 'Выбрать дату и время'
                                : 'До: ${DateFormat('dd.MM.yyyy HH:mm').format(expiry!)}',
                          ),
                          trailing: const Icon(Icons.schedule_outlined),
                          onTap: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(
                              context: context,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                              initialDate: now.add(const Duration(days: 1)),
                            );
                            if (d == null || !context.mounted) return;
                            final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (t == null) return;
                            setDialogState(() {
                              expiry = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                t.hour,
                                t.minute,
                              );
                            });
                          },
                        ),
                      TextField(
                        controller: usesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Лимит использований (опционально)',
                          hintText: 'Например: 10',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Создать'),
                    ),
                  ],
                ),
              ),
            );
            if (ok != true) {
              usesCtrl.dispose();
              return;
            }
            final maxUses = int.tryParse(usesCtrl.text.trim());
            usesCtrl.dispose();
            if (withExpiry && expiry == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Выберите срок ссылки')),
                );
              }
              return;
            }
            setModalState(() => loading = true);
            try {
              await ChatService.createGroupInviteLink(
                _conversation.id,
                expiresAt: withExpiry ? expiry : null,
                maxUses: maxUses,
              );
              await reload();
            } catch (e) {
              setModalState(() {
                loading = false;
                err = userVisibleError(e);
              });
            }
          }

          if (loading) {
            return const SafeArea(
              child: SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (err != null) {
            return SafeArea(
              child: SizedBox(
                height: 260,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(err!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: reload,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link_outlined),
                    title: Text('Ссылка-приглашение'),
                    subtitle:
                        Text('Можно создавать несколько ссылок с лимитами'),
                  ),
                  if (links.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Ссылок пока нет'),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: links.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final link = links[index];
                          final expired = link.expiresAt != null &&
                              link.expiresAt!.isBefore(DateTime.now());
                          final state = link.isRevoked
                              ? 'Отозвана'
                              : (expired
                                  ? 'Истекла'
                                  : (link.isExhausted
                                      ? 'Лимит исчерпан'
                                      : 'Активна'));
                          final sub = <String>[
                            state,
                            if (link.maxUses != null)
                              '${link.usesCount}/${link.maxUses}',
                            if (link.expiresAt != null)
                              'до ${DateFormat('dd.MM.yy HH:mm').format(link.expiresAt!.toLocal())}',
                          ].join(' • ');
                          return ListTile(
                            title: SelectableText(
                              link.inviteLink,
                              maxLines: 1,
                            ),
                            subtitle: Text(sub),
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: 'Копировать',
                                  onPressed: () => copy(link),
                                  icon: const Icon(Icons.copy_outlined),
                                ),
                                if (!link.isRevoked)
                                  IconButton(
                                    tooltip: 'Отозвать',
                                    onPressed: () => revoke(link),
                                    icon: const Icon(Icons.block_outlined),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: createLink,
                          icon: const Icon(Icons.add_link_outlined),
                          label: const Text('Новая ссылка'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: rotateMain,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Ротировать главную'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openJoinRequestsSheet() async {
    if (!_canManageMembers || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<List<ChatGroupJoinRequest>> load() =>
              ChatService.listGroupJoinRequests(
                _conversation.id,
                status: 'pending',
              );
          return FutureBuilder<List<ChatGroupJoinRequest>>(
            future: load(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SafeArea(
                  child: SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (snap.hasError) {
                return SafeArea(
                  child: SizedBox(
                    height: 260,
                    child: Center(child: Text(userVisibleError(snap.error!))),
                  ),
                );
              }
              final items = snap.data ?? const <ChatGroupJoinRequest>[];
              return SafeArea(
                child: SizedBox(
                  height: 440,
                  child: items.isEmpty
                      ? const Center(child: Text('Нет активных заявок'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final row = items[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  row.user.displayName.characters.first
                                      .toUpperCase(),
                                ),
                              ),
                              title: Text(row.user.displayName),
                              subtitle: Text(
                                'Запрос от ${row.requestedAt.day.toString().padLeft(2, '0')}.${row.requestedAt.month.toString().padLeft(2, '0')}.${row.requestedAt.year}',
                              ),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await ChatService
                                            .reviewGroupJoinRequest(
                                          conversationId: _conversation.id,
                                          requestId: row.id,
                                          approve: false,
                                        );
                                        setModalState(() {});
                                        if (mounted) {
                                          await _load();
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text(userVisibleError(e)),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Отклонить'),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      try {
                                        await ChatService
                                            .reviewGroupJoinRequest(
                                          conversationId: _conversation.id,
                                          requestId: row.id,
                                          approve: true,
                                        );
                                        setModalState(() {});
                                        if (mounted) {
                                          await _load();
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text(userVisibleError(e)),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Принять'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openModerationLog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatGroupModerationLogScreen(
          conversation: _conversation,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content:
            const Text('Вы больше не будете получать сообщения в этом чате.'),
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
                            onPressed: (_busy || !_canManagePostingPermissions)
                                ? null
                                : _renameGroup,
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
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Медиа, файлы и ссылки'),
                          subtitle: const Text('Общие фото, видео и документы'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy
                              ? null
                              : () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => ChatMediaGalleryScreen(
                                        conversationId: _conversation.id,
                                      ),
                                    ),
                                  );
                                },
                        ),
                        SwitchListTile(
                          secondary:
                              const Icon(Icons.admin_panel_settings_outlined),
                          title: const Text('Только админы могут писать'),
                          subtitle: Text(
                            _canManagePostingPermissions
                                ? 'Участники смогут только читать сообщения'
                                : 'Нет права управлять этим параметром',
                          ),
                          value: _conversation.onlyAdminsCanPost,
                          onChanged: (_busy || !_canManagePostingPermissions)
                              ? null
                              : (_) => _toggleOnlyAdminsCanPost(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Slow mode'),
                          subtitle: Text(
                            _conversation.slowModeSeconds <= 0
                                ? 'Выключен'
                                : '${_slowModeLabel(_conversation.slowModeSeconds)} между сообщениями',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: (_busy || !_canManagePostingPermissions)
                              ? null
                              : _configureSlowMode,
                        ),
                        ListTile(
                          leading: const Icon(Icons.speed_outlined),
                          title: const Text('Антифлуд (сообщений/мин)'),
                          subtitle: Text(
                            _conversation.antiFloodMaxMessagesPerMinute <= 0
                                ? 'Выключен'
                                : '${_conversation.antiFloodMaxMessagesPerMinute} сообщений/мин',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: (_busy || !_canManagePostingPermissions)
                              ? null
                              : _configureAntiFloodLimit,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.approval_outlined),
                          title: const Text('Вступление по заявкам'),
                          subtitle: Text(
                            _canManageMembers
                                ? 'По инвайту сначала создается заявка'
                                : 'Нет права управлять вступлением',
                          ),
                          value: _conversation.joinByRequestEnabled,
                          onChanged: (_busy || !_canManageMembers)
                              ? null
                              : (_) => _toggleJoinByRequestEnabled(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_add_outlined),
                          title: const Text('Добавить участников'),
                          onTap: (_busy || !_canManageMembers)
                              ? null
                              : _addMembers,
                        ),
                        ListTile(
                          leading: const Icon(Icons.link_outlined),
                          title: const Text('Ссылка-приглашение'),
                          onTap: (_busy || !_canManageMembers)
                              ? null
                              : _openInviteLinkSheet,
                        ),
                        ListTile(
                          leading: const Icon(Icons.pending_actions_outlined),
                          title: const Text('Заявки на вступление'),
                          trailing: _conversation.pendingJoinRequestsCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_conversation.pendingJoinRequestsCount}',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: (_busy || !_canManageMembers)
                              ? null
                              : _openJoinRequestsSheet,
                        ),
                        ListTile(
                          leading: const Icon(Icons.block_outlined),
                          title: const Text('Бан-лист группы'),
                          onTap: (_busy || !_canManageMembers)
                              ? null
                              : _openBansSheet,
                        ),
                        ListTile(
                          leading: const Icon(Icons.history_outlined),
                          title: const Text('История модерации'),
                          onTap: (_busy || !_canManageMembers)
                              ? null
                              : _openModerationLog,
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
                          final canRemove = _canManageMembers &&
                              !isMe &&
                              member.id != _conversation.createdByUserId;
                          final canToggleAdmin =
                              _isCreator && !isMe && !member.isGroupCreator;
                          final canEditPermissions = _isCreator &&
                              !isMe &&
                              !member.isGroupCreator &&
                              member.isGroupAdmin;
                          final roleDetails = <String>[];
                          if (member.canManageMembers) {
                            roleDetails.add('участники');
                          }
                          if (member.canManagePostingPermissions) {
                            roleDetails.add('права чата');
                          }
                          final role = member.isGroupCreator
                              ? 'Создатель'
                              : (member.isGroupAdmin
                                  ? (roleDetails.isEmpty
                                      ? 'Модератор'
                                      : 'Модератор (${roleDetails.join(', ')})')
                                  : null);
                          final restriction = member.sendRestricted
                              ? (member.sendRestrictedUntil == null
                                  ? 'Ограничен: бессрочно'
                                  : 'Ограничен до ${member.sendRestrictedUntil!.toLocal().day.toString().padLeft(2, '0')}.${member.sendRestrictedUntil!.toLocal().month.toString().padLeft(2, '0')}.${member.sendRestrictedUntil!.toLocal().year}')
                              : null;
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
                              [
                                if (role != null) role,
                                if (restriction != null) restriction,
                                formatLastSeen(member.lastSeenAt),
                              ].join(' • '),
                            ),
                            trailing: (canRemove ||
                                    canToggleAdmin ||
                                    canEditPermissions ||
                                    (_canManageMembers &&
                                        !isMe &&
                                        !member.isGroupCreator))
                                ? PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (_busy) return;
                                      if (value == 'remove') {
                                        _removeMember(member);
                                      } else if (value == 'promote') {
                                        _setMemberAdmin(member, true);
                                      } else if (value == 'demote') {
                                        _setMemberAdmin(member, false);
                                      } else if (value == 'permissions') {
                                        _editMemberPermissions(member);
                                      } else if (value == 'restrict') {
                                        _editMemberSendRestriction(member);
                                      } else if (value == 'ban') {
                                        _banMember(member);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (canToggleAdmin &&
                                          !member.isGroupAdmin)
                                        const PopupMenuItem(
                                          value: 'promote',
                                          child: Text('Назначить модератором'),
                                        ),
                                      if (canToggleAdmin && member.isGroupAdmin)
                                        const PopupMenuItem(
                                          value: 'demote',
                                          child: Text('Снять модератора'),
                                        ),
                                      if (canEditPermissions)
                                        const PopupMenuItem(
                                          value: 'permissions',
                                          child: Text('Права модератора'),
                                        ),
                                      if (_canManageMembers &&
                                          !isMe &&
                                          !member.isGroupCreator)
                                        PopupMenuItem(
                                          value: 'restrict',
                                          child: Text(
                                            member.sendRestricted
                                                ? 'Изменить/снять ограничение'
                                                : 'Ограничить отправку',
                                          ),
                                        ),
                                      if (_canManageMembers &&
                                          !isMe &&
                                          !member.isGroupCreator)
                                        const PopupMenuItem(
                                          value: 'ban',
                                          child: Text('Забанить и удалить'),
                                        ),
                                      if (canRemove)
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Удалить из группы'),
                                        ),
                                    ],
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
