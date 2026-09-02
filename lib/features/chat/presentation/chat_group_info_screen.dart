import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/app_router.dart';
import '../../../core/share/system_share.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/presence_format.dart';
import '../../../widgets/app_avatar.dart';
import '../application/chat_inbox_optimistic.dart';
import '../application/chats_hub_refresh_provider.dart';
import '../application/join_requests_bulk.dart';
import 'chat_group_moderation_log_screen.dart';
import 'chat_media_gallery_screen.dart';
import 'widgets/chat_mute_duration_sheet.dart';
import 'widgets/chats_hub_contacts_tab.dart';

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
  static const List<int> _autoDeletePresets = [
    0,
    24 * 3600,
    7 * 24 * 3600,
    30 * 24 * 3600,
  ];

  late ChatConversation _conversation;
  List<ChatUserBrief> _members = [];
  bool _loading = true;
  GroupPaidSettings? _paid;
  bool _busy = false;
  Object? _error;

  int? get _myId => AuthService.instance.currentUser?.id;

  bool get _isCreator =>
      _myId != null && _conversation.createdByUserId == _myId;

  bool get _amIAdmin => _conversation.amIGroupAdmin || _isCreator;
  bool get _canManageMembers => _conversation.amICanManageMembers || _isCreator;
  bool get _canManagePostingPermissions =>
      _conversation.amICanManagePostingPermissions || _isCreator;
  bool get _canChangeInfo => _conversation.amICanChangeInfo || _isCreator;
  bool get _canInviteUsers => _conversation.amICanInviteUsers || _isCreator;

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
      GroupPaidSettings? paid;
      try {
        paid = await PaidFeaturesService.getGroupPaidSettings(_conversation.id);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _members = members;
        _paid = paid;
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

  Future<void> _changeGroupPhoto() async {
    if (!_canChangeInfo || _busy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (!mounted || picked == null) return;
    setState(() => _busy = true);
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: picked,
        fileType: 'image',
      );
      var url = uploaded.url?.trim();
      if (url == null || url.isEmpty) {
        throw StateError('upload_missing_url');
      }
      url = ServerConfig.resolveMediaUrl(url);
      final conv = await ChatService.updateGroupAvatar(
        conversationId: _conversation.id,
        avatarUrl: url,
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

  void _applyConversation(ChatConversation next) {
    setState(() {
      _conversation = next;
      _busy = false;
    });
    widget.onConversationChanged?.call(next);
  }

  Future<void> _commitConversation({
    required ChatConversation optimistic,
    required Future<ChatConversation> Function() request,
  }) async {
    final previous = _conversation;
    _applyConversation(optimistic);
    try {
      final conv = await request();
      if (!mounted) return;
      _applyConversation(conv);
    } catch (e) {
      if (!mounted) return;
      _applyConversation(previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleMute() async {
    final choice = await showChatMuteDurationSheet(
      context,
      currentlyMuted: _conversation.muted,
      mutedUntil: _conversation.mutedUntil,
      currentNotifyMode: _conversation.notifyMode,
    );
    if (choice == null || !mounted) return;
    final muted = !choice.unmute;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(choice.snackLabel)),
    );
    await _commitConversation(
      optimistic: ChatInboxOptimistic.applyMute(
        _conversation,
        muted: muted,
        until: choice.until,
        notifyMode: choice.notifyMode,
      ),
      request: () => ChatService.setMuted(
        conversationId: _conversation.id,
        muted: muted,
        mutedUntil: muted ? choice.until : null,
        notifyMode: choice.notifyMode,
      ).then((_) => ChatInboxOptimistic.applyMute(
            _conversation,
            muted: muted,
            until: choice.until,
            notifyMode: choice.notifyMode,
          )),
    );
  }

  Future<void> _editGroupPaid() async {
    if (!_canChangeInfo || _busy) return;
    final current = _paid;
    final priceController = TextEditingController(
      text: '${current?.monthlyPriceStars ?? 50}',
    );
    var isPaid = current?.isPaid ?? false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Платная группа',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Подписка за ★'),
                    value: isPaid,
                    onChanged: (v) => setLocal(() => isPaid = v),
                  ),
                  if (isPaid)
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '★ в месяц',
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final price = int.tryParse(priceController.text.trim()) ?? 0;
    priceController.dispose();
    if (ok != true || !mounted) return;
    try {
      final next = await PaidFeaturesService.setGroupPaidSettings(
        _conversation.id,
        isPaid: isPaid,
        monthlyPriceStars: price,
      );
      if (!mounted) return;
      setState(() => _paid = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _subscribeGroup() async {
    final paid = _paid;
    if (paid == null || !paid.isPaid || paid.subscribed) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Подписка на группу',
      body: 'Доступ на 30 дней. С баланса спишется ${paid.monthlyPriceStars} ★.',
      amountStars: paid.monthlyPriceStars,
      confirmLabel: 'Оплатить',
    );
    if (!ok || !mounted) return;
    try {
      final next = await PaidFeaturesService.subscribeGroup(_conversation.id);
      if (!mounted) return;
      setState(() => _paid = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подписка оформлена')),
      );
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _toggleOnlyAdminsCanPost() async {
    if (!_canManagePostingPermissions) return;
    final next = !_conversation.onlyAdminsCanPost;
    await _commitConversation(
      optimistic: _conversation.copyWith(onlyAdminsCanPost: next),
      request: () => ChatService.setGroupOnlyAdminsCanPost(
        conversationId: _conversation.id,
        onlyAdminsCanPost: next,
      ),
    );
  }

  Future<void> _toggleProtectContent() async {
    if (!_canManagePostingPermissions) return;
    final next = !_conversation.protectContent;
    await _commitConversation(
      optimistic: _conversation.copyWith(protectContent: next),
      request: () => ChatService.setGroupProtectContent(
        conversationId: _conversation.id,
        enabled: next,
      ),
    );
  }

  Future<void> _toggleIsForum() async {
    if (!_canChangeInfo) return;
    final next = !_conversation.isForum;
    if (!next) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Выключить темы?'),
          content: const Text(
            'Группа снова станет обычным чатом. Темы и история сохранятся '
            'и вернутся, если включить темы снова.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Выключить'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Темы включены — в чате появится General и новые темы'
              : 'Темы выключены — данные тем сохранены',
        ),
      ),
    );
    await _commitConversation(
      optimistic: _conversation.copyWith(isForum: next),
      request: () => ChatService.setGroupIsForum(
        conversationId: _conversation.id,
        enabled: next,
      ),
    );
  }

  Future<void> _toggleJoinByRequestEnabled() async {
    if (!_canManageMembers) return;
    final next = !_conversation.joinByRequestEnabled;
    await _commitConversation(
      optimistic: _conversation.copyWith(joinByRequestEnabled: next),
      request: () => ChatService.setGroupJoinByRequestEnabled(
        conversationId: _conversation.id,
        enabled: next,
      ),
    );
  }

  String _slowModeLabel(int value) {
    if (value <= 0) return 'Выключен';
    if (value < 60) return '$value сек';
    final minutes = value ~/ 60;
    return '$minutes мин';
  }

  String _autoDeleteLabel(int value) {
    if (value <= 0) return 'Выключено';
    if (value < 3600) return '${value ~/ 60} мин';
    if (value < 24 * 3600) return '${value ~/ 3600} ч';
    final days = value ~/ (24 * 3600);
    return '$days дн.';
  }

  Future<void> _configureAutoDelete() async {
    if (!_canManagePostingPermissions) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.auto_delete_outlined),
              title: Text('Автоудаление сообщений'),
              subtitle: Text('Старые сообщения удаляются у всех участников'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _autoDeletePresets
                  .map(
                    (seconds) => ChoiceChip(
                      label: Text(_autoDeleteLabel(seconds)),
                      selected: _conversation.autoDeleteSeconds == seconds,
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
    if (picked == null ||
        picked == _conversation.autoDeleteSeconds ||
        !mounted) {
      return;
    }
    await _commitConversation(
      optimistic: _conversation.copyWith(autoDeleteSeconds: picked),
      request: () => ChatService.setAutoDeleteSeconds(
        conversationId: _conversation.id,
        seconds: picked,
      ),
    );
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
    await _commitConversation(
      optimistic: _conversation.copyWith(slowModeSeconds: picked),
      request: () => ChatService.setGroupSlowModeSeconds(
        conversationId: _conversation.id,
        seconds: picked,
      ),
    );
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
    await _commitConversation(
      optimistic: _conversation.copyWith(antiFloodMaxMessagesPerMinute: picked),
      request: () => ChatService.setGroupAntiFloodLimit(
        conversationId: _conversation.id,
        maxMessagesPerMinute: picked,
      ),
    );
  }

  Future<void> _addMembers() async {
    if (!_canInviteUsers) return;
    List<ChatContact> contacts;
    try {
      contacts = await ChatService.listContacts();
    } catch (e) {
      if (!mounted) return;
      final retry = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Не удалось загрузить контакты'),
          content: Text(userVisibleError(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: const Text('Закрыть'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'contacts'),
              child: const Text('К контактам'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (retry == 'retry') {
        await _addMembers();
      } else if (retry == 'contacts') {
        requestChatsHubTab(ChatsHubContactsTab.contactsTabIndex);
        context.go(ChatsRoute.path);
      }
      return;
    }
    final memberIds = _members.map((m) => m.id).toSet();
    final candidates = contacts
        .map((c) => c.user)
        .where((u) => !memberIds.contains(u.id))
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      final openContacts = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нет контактов'),
          content: const Text(
            'Добавьте людей в контакты, чтобы пригласить их в группу.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('К контактам'),
            ),
          ],
        ),
      );
      if (openContacts == true && mounted) {
        requestChatsHubTab(ChatsHubContactsTab.contactsTabIndex);
        context.go(ChatsRoute.path);
      }
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
    bool canChangeInfo = member.canChangeInfo;
    bool canDeleteMessages = member.canDeleteMessages;
    bool canPinMessages = member.canPinMessages;
    bool canInviteUsers = member.canInviteUsers;
    bool canManageVideoChats = member.canManageVideoChats;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Права: ${member.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Изменять информацию'),
                  subtitle: const Text('Название и фото группы'),
                  value: canChangeInfo,
                  onChanged: (v) => setModalState(() => canChangeInfo = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Удалять сообщения'),
                  subtitle: const Text('Удалять чужие сообщения у всех'),
                  value: canDeleteMessages,
                  onChanged: (v) =>
                      setModalState(() => canDeleteMessages = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Закреплять сообщения'),
                  value: canPinMessages,
                  onChanged: (v) => setModalState(() => canPinMessages = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Приглашать пользователей'),
                  subtitle: const Text('Добавлять участников и ссылки'),
                  value: canInviteUsers,
                  onChanged: (v) => setModalState(() => canInviteUsers = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Управлять участниками'),
                  subtitle: const Text('Ограничивать, банить, заявки'),
                  value: canManageMembers,
                  onChanged: (v) => setModalState(() => canManageMembers = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Настройки чата'),
                  subtitle: const Text('Slow mode, «только админы» и т.п.'),
                  value: canManagePostingPermissions,
                  onChanged: (v) => setModalState(
                    () => canManagePostingPermissions = v,
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Групповые звонки'),
                  subtitle: const Text('Начинать видео/аудиозвонки'),
                  value: canManageVideoChats,
                  onChanged: (v) =>
                      setModalState(() => canManageVideoChats = v),
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
        canChangeInfo: canChangeInfo,
        canDeleteMessages: canDeleteMessages,
        canPinMessages: canPinMessages,
        canInviteUsers: canInviteUsers,
        canManageVideoChats: canManageVideoChats,
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
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                userVisibleError(snap.error!),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => setModalState(() {}),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final items = snap.data ?? const <ChatGroupBanEntry>[];
                return SafeArea(
                  child: SizedBox(
                    height: 420,
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Бан-лист пуст'),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Закрыть'),
                                  ),
                                ],
                              ),
                            ),
                          )
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
    if (!_canInviteUsers || !mounted) return;
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

          Future<void> share(ChatGroupInviteLink link) async {
            final title = _conversation.title?.trim();
            final subject = (title != null && title.isNotEmpty)
                ? 'Приглашение в «$title»'
                : 'Приглашение в группу HanWe';
            await SystemShare.shareText(
              context,
              text: link.inviteLink,
              subject: subject,
              webSnackBarText: 'Ссылка скопирована',
            );
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
                                    tooltip: 'Поделиться',
                                    onPressed: () => share(link),
                                    icon: const Icon(Icons.share_outlined),
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
      builder: (ctx) => _GroupJoinRequestsSheet(
        conversationId: _conversation.id,
        onChanged: () {
          if (mounted) unawaited(_load());
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
    try {
      await ChatService.leaveGroup(conversationId: _conversation.id);
      if (!mounted) return;
      widget.onLeftGroup?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_leaveGroup()),
          ),
        ),
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
                        Center(
                          child: Builder(
                            builder: (context) {
                              final avatar = Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundImage: resolvedAvatarImage(
                                      _conversation.avatarUrl,
                                      decodeWidth: 160,
                                    ),
                                    child: resolvedAvatarImage(
                                              _conversation.avatarUrl,
                                              decodeWidth: 160,
                                            ) ==
                                            null
                                        ? Text(
                                            _conversation
                                                .displayTitle.characters
                                                .first
                                                .toUpperCase(),
                                            style:
                                                theme.textTheme.headlineMedium,
                                          )
                                        : null,
                                  ),
                                  if (_canChangeInfo)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.camera_alt_outlined,
                                        size: 16,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                ],
                              );
                              if (!_canChangeInfo) return avatar;
                              return GestureDetector(
                                onTap: _busy ? null : _changeGroupPhoto,
                                child: avatar,
                              );
                            },
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
                            onPressed: (_busy || !_canChangeInfo)
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
                                        protectContent:
                                            _conversation.protectContent,
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
                        SwitchListTile(
                          secondary: const Icon(Icons.lock_outline),
                          title: const Text('Запретить пересылку'),
                          subtitle: Text(
                            _canManagePostingPermissions
                                ? 'Участники не смогут пересылать и сохранять сообщения'
                                : 'Нет права управлять этим параметром',
                          ),
                          value: _conversation.protectContent,
                          onChanged: (_busy || !_canManagePostingPermissions)
                              ? null
                              : (_) => _toggleProtectContent(),
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.topic_outlined),
                          title: const Text('Темы (форум)'),
                          subtitle: Text(
                            _canChangeInfo
                                ? 'Разделить группу на темы вроде Telegram Topics'
                                : 'Нет права менять информацию группы',
                          ),
                          value: _conversation.isForum,
                          onChanged: (_busy || !_canChangeInfo)
                              ? null
                              : (_) => _toggleIsForum(),
                        ),
                        if (_canChangeInfo)
                          ListTile(
                            leading: const Icon(Icons.workspace_premium_outlined),
                            title: const Text('Платная группа'),
                            subtitle: Text(
                              _paid?.isPaid == true
                                  ? '${_paid!.monthlyPriceStars} ★ / мес'
                                  : 'Бесплатный вход',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _busy ? null : _editGroupPaid,
                          )
                        else if (_paid?.isPaid == true)
                          ListTile(
                            leading: const Icon(Icons.workspace_premium_outlined),
                            title: const Text('Подписка ★'),
                            subtitle: Text(
                              _paid!.subscribed
                                  ? 'Активна'
                                  : '${_paid!.monthlyPriceStars} ★ / мес',
                            ),
                            trailing: _paid!.subscribed
                                ? const Icon(Icons.check_circle_outline)
                                : FilledButton(
                                    onPressed: _busy ? null : _subscribeGroup,
                                    child: const Text('Оплатить'),
                                  ),
                          ),
                        ListTile(
                          leading: const Icon(Icons.auto_delete_outlined),
                          title: const Text('Автоудаление'),
                          subtitle: Text(
                            _conversation.autoDeleteSeconds <= 0
                                ? 'Выключено'
                                : 'Через ${_autoDeleteLabel(_conversation.autoDeleteSeconds)}',
                          ),
                          trailing: _canManagePostingPermissions
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: (_busy || !_canManagePostingPermissions)
                              ? null
                              : _configureAutoDelete,
                        ),
                        ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Slow mode'),
                          subtitle: Text(
                            _conversation.slowModeSeconds <= 0
                                ? 'Выключен'
                                : '${_slowModeLabel(_conversation.slowModeSeconds)} между сообщениями',
                          ),
                          trailing: _canManagePostingPermissions
                              ? const Icon(Icons.chevron_right)
                              : null,
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
                          trailing: _canManagePostingPermissions
                              ? const Icon(Icons.chevron_right)
                              : null,
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
                          onTap: (_busy || !_canInviteUsers)
                              ? null
                              : _addMembers,
                        ),
                        ListTile(
                          leading: const Icon(Icons.link_outlined),
                          title: const Text('Ссылка-приглашение'),
                          onTap: (_busy || !_canInviteUsers)
                              ? null
                              : _openInviteLinkSheet,
                        ),
                        if (_canManageMembers) ...[
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
                            onTap: _busy ? null : _openJoinRequestsSheet,
                          ),
                          ListTile(
                            leading: const Icon(Icons.block_outlined),
                            title: const Text('Бан-лист группы'),
                            onTap: _busy ? null : _openBansSheet,
                          ),
                          ListTile(
                            leading: const Icon(Icons.history_outlined),
                            title: const Text('История модерации'),
                            onTap: _busy ? null : _openModerationLog,
                          ),
                        ],
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
                          if (member.canChangeInfo) {
                            roleDetails.add('инфо');
                          }
                          if (member.canDeleteMessages) {
                            roleDetails.add('удаление');
                          }
                          if (member.canPinMessages) {
                            roleDetails.add('пин');
                          }
                          if (member.canInviteUsers) {
                            roleDetails.add('инвайт');
                          }
                          if (member.canManageMembers) {
                            roleDetails.add('участники');
                          }
                          if (member.canManagePostingPermissions) {
                            roleDetails.add('настройки');
                          }
                          if (member.canManageVideoChats) {
                            roleDetails.add('звонки');
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

class _GroupJoinRequestsSheet extends StatefulWidget {
  const _GroupJoinRequestsSheet({
    required this.conversationId,
    required this.onChanged,
  });

  final int conversationId;
  final VoidCallback onChanged;

  @override
  State<_GroupJoinRequestsSheet> createState() =>
      _GroupJoinRequestsSheetState();
}

class _GroupJoinRequestsSheetState extends State<_GroupJoinRequestsSheet> {
  List<ChatGroupJoinRequest>? _items;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _items = null;
    });
    try {
      final rows = await ChatService.listGroupJoinRequests(
        widget.conversationId,
        status: 'pending',
      );
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _reviewOne(ChatGroupJoinRequest row, {required bool approve}) async {
    try {
      await ChatService.reviewGroupJoinRequest(
        conversationId: widget.conversationId,
        requestId: row.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _items = [...?_items]..removeWhere((r) => r.id == row.id);
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _reviewAll({required bool approve}) async {
    final items = List<ChatGroupJoinRequest>.from(_items ?? const []);
    if (items.isEmpty || _busy) return;
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отклонить все заявки?'),
          content: Text('Будет отклонено: ${items.length}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отклонить все'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    final result = await reviewJoinRequestsBulk<ChatGroupJoinRequest>(
      items: items,
      review: (row) => ChatService.reviewGroupJoinRequest(
        conversationId: widget.conversationId,
        requestId: row.id,
        approve: approve,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          joinRequestsBulkSnackMessage(approve: approve, result: result),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SafeArea(
      child: SizedBox(
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items == null
                          ? 'Заявки'
                          : 'Заявки (${items.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (items != null && items.length > 1) ...[
                    TextButton(
                      onPressed: _busy ? null : () => _reviewAll(approve: false),
                      child: const Text('Отклонить все'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _reviewAll(approve: true),
                      child: const Text('Принять все'),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userVisibleError(_error!),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reload,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : items == null
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Нет активных заявок'),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const Text('Закрыть'),
                                    ),
                                  ],
                                ),
                              ),
                            )
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
                                        onPressed: _busy
                                            ? null
                                            : () => _reviewOne(
                                                  row,
                                                  approve: false,
                                                ),
                                        child: const Text('Отклонить'),
                                      ),
                                      FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _reviewOne(
                                                  row,
                                                  approve: true,
                                                ),
                                        child: const Text('Принять'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
