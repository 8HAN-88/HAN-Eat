import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../app/app_router.dart';
import '../core/theme/app_tokens.dart';
import '../core/share/system_share.dart';
import '../features/chat/application/chat_open_direct.dart';
import '../features/chat/application/chat_ready_outgoing.dart';
import '../features/chat/application/chat_thread_prefetch.dart';
import '../features/chat/presentation/chat_people_search_screen.dart';
import '../models/chat_models.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/channel_service.dart';
import '../services/repost_service.dart';
import '../services/share_link_service.dart';
import '../utils/api_error_parser.dart';
import 'app_avatar.dart';
import 'chat_reel_preview.dart';

class ShareActionSheet {
  static Future<void> _shareAfterSheetClosed(
    BuildContext rootContext, {
    required String text,
    required String subject,
  }) async {
    await SystemShare.shareText(
      rootContext,
      text: text,
      subject: subject,
      preShareDelay: const Duration(milliseconds: 180),
      webSnackBarText: 'Ссылка скопирована',
    );
  }

  static Future<void> showForPost(
    BuildContext context, {
    required PostModel post,
    Future<void> Function()? onRepostToWall,
  }) async {
    final link = ShareLinkService.postLink(post.id);
    await _show(context, post: post, link: link, onRepostToWall: onRepostToWall);
  }

  static Future<void> showForReel(
    BuildContext context, {
    required PostModel reel,
    Future<void> Function()? onRepostToWall,
  }) async {
    final link = ShareLinkService.reelLink(reel.id);
    await _show(
      context,
      post: reel,
      link: link,
      onRepostToWall: onRepostToWall,
    );
  }

  static Future<void> _show(
    BuildContext context, {
    required PostModel post,
    required String link,
    Future<void> Function()? onRepostToWall,
  }) async {
    final width = MediaQuery.sizeOf(context).width;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useRootNavigator: true,
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      builder: (ctx) => _PostShareSheet(
        post: post,
        link: link,
        onRepostToWall: onRepostToWall,
      ),
    );
  }
}

class _PostShareSheet extends StatefulWidget {
  const _PostShareSheet({
    required this.post,
    required this.link,
    this.onRepostToWall,
  });

  final PostModel post;
  final String link;
  final Future<void> Function()? onRepostToWall;

  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  final _searchCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  List<ChatConversation> _chats = const [];
  bool _loadingChats = true;
  bool _loadingChannels = false;
  bool _sendingToChat = false;

  bool get _isOwnPost {
    final me = AuthService.instance.currentUser?.id;
    return me != null && me == widget.post.userId;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadChats());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final chats = await ChatOpenDirect.listForPicker();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _loadingChats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingChats = false);
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(this.context).showSnackBar(
      const SnackBar(content: Text('Ссылка скопирована')),
    );
  }

  Future<void> _shareViaSystem(BuildContext context) async {
    final text = ShareLinkService.sharedPostShareText(widget.post);
    Navigator.pop(context);
    await ShareActionSheet._shareAfterSheetClosed(
      this.context,
      text: text,
      subject: widget.post.title ?? 'Пост',
    );
  }

  Future<void> _repostToChannel(BuildContext context) async {
    if (_loadingChannels) return;
    setState(() => _loadingChannels = true);
    try {
      final channelsResp = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        mine: true,
      );
      final channels = channelsResp.items;
      if (!mounted) return;
      if (channels.isEmpty) {
        Navigator.pop(context);
        if (!this.context.mounted) return;
        final create = await showDialog<bool>(
          context: this.context,
          builder: (ctx) => AlertDialog(
            title: const Text('Нет каналов'),
            content: const Text(
              'Создайте канал или станьте администратором, чтобы публиковать репосты.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Закрыть'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Создать канал'),
              ),
            ],
          ),
        );
        if (create == true && this.context.mounted) {
          await this.context.push(CreateChannelRoute.path);
        }
        return;
      }

      final picked = await showModalBottomSheet<dynamic>(
        context: this.context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Выберите канал',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final c in channels)
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: resolvedAvatarImage(c.avatarUrl),
                    child: resolvedAvatarImage(c.avatarUrl) == null
                        ? Text(c.name.isNotEmpty ? c.name[0] : '?')
                        : null,
                  ),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      );

      if (picked == null || !mounted) return;

      final commentResult = await showDialog<String?>(
        context: this.context,
        builder: (ctx) => _ChannelRepostCommentDialog(channelName: picked.name),
      );
      if (!mounted) return;
      if (commentResult == null) return;

      await RepostService.repostToChannel(
        postId: widget.post.id,
        channelId: picked.id,
        comment: commentResult.isEmpty ? null : commentResult,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
            content: Text('Репост опубликован в канале «${picked.name}».')),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleAuthError(e, fallback: 'Не удалось опубликовать репост'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_repostToChannel(this.context)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleAuthError(e, fallback: 'Не удалось опубликовать репост'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_repostToChannel(this.context)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _openPeopleSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const ChatPeopleSearchScreen(),
      ),
    );
    await _loadChats();
  }

  Future<void> _sendToSelected() async {
    if (_sendingToChat) return;
    final selected = _chats
        .where((c) => _selectedIds.contains(c.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      if (_chats.isEmpty) {
        await _openPeopleSearch();
      }
      return;
    }
    setState(() => _sendingToChat = true);
    try {
      final shareText = ShareLinkService.sharedPostShareText(
        widget.post,
        comment: _messageCtrl.text,
      );
      for (final picked in selected) {
        final pending = ChatReadyOutgoing(
          tempId: newReadyOutgoingTempId(),
          clientMessageId: const Uuid().v4(),
          type: 'text',
          content: shareText,
        );
        await persistReadyOutgoing(
          conversationId: picked.id,
          pending: pending,
          optimistic: ChatMessage(
            id: pending.tempId,
            conversationId: picked.id,
            senderId: AuthService.instance.currentUser?.id ?? 0,
            type: 'text',
            content: shareText,
            createdAt: DateTime.now(),
            isMine: true,
            clientMessageId: pending.clientMessageId,
          ),
        );
        unawaited(
          sendChatReadyOutgoing(
            conversationId: picked.id,
            pending: pending,
          ),
        );
        unawaited(ChatThreadPrefetch.warm(picked.id));
      }
      if (!mounted) return;
      final openPath = ChatThreadRoute.pathForId(selected.first.id);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push(openPath);
    } on ApiClientException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleAuthError(e, fallback: 'Не удалось отправить в чат'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_sendToSelected()),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_sendToSelected()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingToChat = false);
    }
  }

  List<ChatConversation> get _filteredChats {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _chats;
    return _chats.where((c) {
      final title = c.displayTitle.toLowerCase();
      final username = c.peer?.username?.toLowerCase() ?? '';
      return title.contains(q) || username.contains(q);
    }).toList(growable: false);
  }

  String? _chatAvatar(ChatConversation chat) {
    if (chat.isSaved) return null;
    final direct = chat.avatarUrl?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return chat.peer?.avatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            children: [
              const Text(
                'Отправить',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SharedPostCard(
                postId: widget.post.id,
                url: widget.link,
                initialPost: widget.post,
                place: SharedPostCardPlace.preview,
                showActions: false,
                mine: true,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Поиск',
                    isDense: true,
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _peopleGrid(scheme)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _messageCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Напишите сообщение…',
                    isDense: true,
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sendingToChat || _selectedIds.isEmpty
                        ? null
                        : _sendToSelected,
                    child: Text(
                      _sendingToChat
                          ? 'Отправка…'
                          : _selectedIds.isEmpty
                              ? 'Отправить'
                              : 'Отправить${_selectedIds.length > 1 ? ' (${_selectedIds.length})' : ''}',
                    ),
                  ),
                ),
              ),
              _moreActions(scheme),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peopleGrid(ColorScheme scheme) {
    if (_loadingChats) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final items = _filteredChats;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _chats.isEmpty ? 'Нет чатов' : 'Никого не нашли',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openPeopleSearch,
              child: const Text('Найти людей'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 108,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final chat = items[i];
        final selected = _selectedIds.contains(chat.id);
        return InkWell(
          onTap: () {
            setState(() {
              if (selected) {
                _selectedIds.remove(chat.id);
              } else {
                _selectedIds.add(chat.id);
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  chat.isSaved
                      ? CircleAvatar(
                          radius: 28,
                          backgroundColor: scheme.primaryContainer,
                          child: Icon(
                            Icons.bookmark_rounded,
                            color: scheme.onPrimaryContainer,
                          ),
                        )
                      : AppUserAvatar(
                          imageUrl: _chatAvatar(chat),
                          displayName: chat.displayTitle,
                          radius: 28,
                        ),
                  if (selected)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                chat.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _moreActions(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onRepostToWall != null && !_isOwnPost)
            _iconAction(
              icon: Icons.autorenew_rounded,
              label: 'На стену',
              onTap: () async {
                Navigator.pop(context);
                await widget.onRepostToWall!.call();
              },
            ),
          if (!_isOwnPost)
            _iconAction(
              icon: Icons.campaign_outlined,
              label: 'В канал',
              onTap: _loadingChannels ? null : () => _repostToChannel(context),
            ),
          _iconAction(
            icon: Icons.link_rounded,
            label: 'Ссылка',
            onTap: () => _copyLink(context),
          ),
          _iconAction(
            icon: Icons.ios_share_rounded,
            label: 'Ещё',
            onTap: () => _shareViaSystem(context),
          ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Комментарий к репосту в канал (как «на стену»).
class _ChannelRepostCommentDialog extends StatefulWidget {
  const _ChannelRepostCommentDialog({required this.channelName});

  final String channelName;

  @override
  State<_ChannelRepostCommentDialog> createState() =>
      _ChannelRepostCommentDialogState();
}

class _ChannelRepostCommentDialogState
    extends State<_ChannelRepostCommentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Репост в «${widget.channelName}»'),
      content: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Комментарий (опционально)',
            hintText: 'Добавьте текст к репосту…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
          ),
          maxLines: 4,
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Опубликовать'),
        ),
      ],
    );
  }
}
