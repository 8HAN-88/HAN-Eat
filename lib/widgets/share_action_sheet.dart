import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/share/system_share.dart';
import '../models/post_model.dart';
import '../models/recipe.dart';
import '../services/channel_service.dart';
import '../services/repost_service.dart';
import '../services/share_link_service.dart';
import '../utils/api_error_parser.dart';

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PostShareSheet(
        post: reel,
        link: link,
        onRepostToWall: onRepostToWall,
      ),
    );
  }

  static Future<void> showForRecipe(
    BuildContext context, {
    required Recipe recipe,
  }) async {
    final link = ShareLinkService.recipeLink(recipe.id);
    final text = ShareLinkService.recipeShareText(recipe);
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Поделиться',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Скопировать ссылку'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка скопирована')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Поделиться через...'),
              onTap: () async {
                Navigator.pop(ctx);
                await _shareAfterSheetClosed(
                  context,
                  text: text,
                  subject: recipe.translatedTitle ?? recipe.title,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
                    backgroundImage: c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
                    child: c.avatarUrl == null ? Text(c.name.isNotEmpty ? c.name[0] : '?') : null,
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
        SnackBar(content: Text('Репост опубликован в канале «${picked.name}».')),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(userVisibleAuthError(e, fallback: 'Не удалось опубликовать репост'))),
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

class _ChannelRepostCommentDialogState extends State<_ChannelRepostCommentDialog> {
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
          decoration: const InputDecoration(
            labelText: 'Комментарий (опционально)',
            hintText: 'Добавьте текст к репосту…',
            border: OutlineInputBorder(),
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
