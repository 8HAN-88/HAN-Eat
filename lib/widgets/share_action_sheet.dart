import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/app_tokens.dart';
import '../core/share/system_share.dart';
import '../features/chat/application/chat_open_direct.dart';
import '../features/chat/application/chat_ready_outgoing.dart';
import '../features/chat/application/chat_thread_prefetch.dart';
import '../models/chat_models.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/channel_service.dart';
import '../services/repost_service.dart';
import '../services/custom_emoji_registry.dart';
import '../services/share_link_service.dart';
import '../utils/api_error_parser.dart';
import 'app_avatar.dart';
import 'highlighted_text.dart';
import 'chat_target_picker_sheet.dart';

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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PostShareSheet(
        post: post,
        link: link,
        onRepostToWall: onRepostToWall,
      ),
    );
  }

  static Future<void> showForReel(
    BuildContext context, {
    required PostModel reel,
    Future<void> Function()? onRepostToWall,
  }) async {
    final link = ShareLinkService.reelLink(reel.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PostShareSheet(
        post: reel,
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
  bool _loadingChannels = false;
  bool _sendingToChat = false;

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(this.context).showSnackBar(
      const SnackBar(content: Text('Ссылка скопирована')),
    );
  }

  Future<void> _shareViaSystem(BuildContext context) async {
    final text = widget.post.type == 'reel'
        ? ShareLinkService.reelShareText(widget.post)
        : ShareLinkService.postShareText(widget.post);
    Navigator.pop(context);
    await ShareActionSheet._shareAfterSheetClosed(
      this.context,
      text: text,
      subject: previewTextWithCustomEmoji(widget.post.title ?? 'Пост'),
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
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text(
              'Нет каналов для публикации. Создайте канал или станьте администратором.',
            ),
          ),
        );
        return;
      }

      final picked = await showModalBottomSheet<Channel>(
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
                        ? Text(avatarLetterWithCustomEmoji(c.name))
                        : null,
                  ),
                  title: HighlightedText(
                    text: c.name,
                    style: Theme.of(context).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
            content: Text(
              'Репост опубликован в канале «${previewTextWithCustomEmoji(picked.name)}».',
            )),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
            content: Text(userVisibleAuthError(e,
                fallback: 'Не удалось опубликовать репост'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleAuthError(e, fallback: 'Не удалось опубликовать репост'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _sendToChat(BuildContext context) async {
    if (_sendingToChat) return;
    setState(() => _sendingToChat = true);
    try {
      final chats = await ChatOpenDirect.listForPicker();
      if (!mounted) return;
      if (chats.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Нет чатов для отправки')),
        );
        return;
      }
      final picked = await showChatTargetPicker(
        this.context,
        title: 'Отправить в чат',
        chats: chats,
      );
      if (picked == null || !mounted) return;
      final shareText = widget.post.type == 'reel'
          ? ShareLinkService.reelShareText(widget.post)
          : ShareLinkService.postShareText(widget.post);
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
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            'Отправлено в «${previewTextWithCustomEmoji(picked.displayTitle)}»',
          ),
        ),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
            content: Text(
          userVisibleAuthError(e, fallback: 'Не удалось отправить в чат'),
        )),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _sendingToChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Поделиться',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (widget.onRepostToWall != null)
            ListTile(
              leading: const Icon(Icons.autorenew),
              title: const Text('Репост на стену'),
              onTap: () async {
                Navigator.pop(context);
                await widget.onRepostToWall!.call();
              },
            ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Репост в канал'),
            onTap: _loadingChannels ? null : () => _repostToChannel(context),
          ),
          ListTile(
            leading: const Icon(Icons.send_rounded),
            title: const Text('Отправить в чат'),
            onTap: _sendingToChat ? null : () => _sendToChat(context),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Скопировать ссылку'),
            onTap: () => _copyLink(context),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Поделиться через...'),
            onTap: () => _shareViaSystem(context),
          ),
          const SizedBox(height: 6),
        ],
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
      title: Text(
        'Репост в «${previewTextWithCustomEmoji(widget.channelName)}»',
      ),
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
