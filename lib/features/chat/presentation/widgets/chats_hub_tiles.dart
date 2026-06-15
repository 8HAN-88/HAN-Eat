import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/channel_service.dart';
import '../../../../services/server_config.dart';

class ChatHubTile extends StatelessWidget {
  const ChatHubTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
  });

  final ChatConversation chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _preview(ChatMessage? msg) {
    if (msg == null) {
      return chat.isSaved ? 'Сохраняйте сообщения и заметки' : 'Нет сообщений';
    }
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'poll') {
      final poll = msg.poll;
      if (poll != null) return chatPollPreviewText(poll);
      return '📊 Опрос';
    }
    if (msg.type == 'image') return '📷 Фото';
    if (msg.type == 'video') return '🎬 Видео';
    if (msg.type == 'file') {
      final name = msg.content.trim();
      return name.isEmpty ? '📎 Файл' : '📎 $name';
    }
    if (chat.isGroup && (msg.senderName?.isNotEmpty ?? false)) {
      return '${msg.senderName}: ${msg.content}';
    }
    return msg.content;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = chat.lastMessage;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: chat.isSaved
          ? CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.bookmark_rounded,
                color: scheme.onPrimaryContainer,
              ),
            )
          : chat.isGroup
              ? ChatHubGroupAvatar(members: chat.membersPreview)
              : ChatHubUserAvatar(
                  user: chat.peer ?? const ChatUserBrief(id: 0, name: 'Чат'),
                ),
      title: Row(
        children: [
          if (chat.pinned) ...[
            Icon(Icons.push_pin, size: 14, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          if (chat.muted) ...[
            Icon(Icons.notifications_off_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight:
                    chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _preview(last),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chat.unreadCount > 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            chatHubFormatInboxTime(chat.updatedAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (chat.unreadCount > 0) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: scheme.primary,
              child: Text(
                chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatHubRecommendedChannelChip extends StatelessWidget {
  const ChatHubRecommendedChannelChip({
    super.key,
    required this.channel,
    required this.onTap,
  });

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatHubChannelAvatar(channel: channel),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatHubGroupAvatar extends StatelessWidget {
  const ChatHubGroupAvatar({super.key, required this.members});

  final List<ChatUserBrief> members;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (members.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.groups_rounded, color: scheme.onPrimaryContainer),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        members.first.displayName.characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class ChatHubUserAvatar extends StatelessWidget {
  const ChatHubUserAvatar({super.key, required this.user});

  final ChatUserBrief user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final resolved = url != null && url.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(url)
        : null;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage: resolved != null
              ? ResizeImage(
                  CachedNetworkImageProvider(resolved),
                  width: 96,
                )
              : null,
          child: resolved == null
              ? Text(
                  chatHubAvatarLetter(user.displayName),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : null,
        ),
        if (user.isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class ChatHubChannelAvatar extends StatelessWidget {
  const ChatHubChannelAvatar({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final url = channel.avatarUrl;
    final resolved = url != null && url.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(url)
        : null;
    return CircleAvatar(
      radius: 24,
      backgroundImage: resolved != null
          ? ResizeImage(CachedNetworkImageProvider(resolved), width: 96)
          : null,
      child: resolved == null
          ? Text(
              chatHubAvatarLetter(channel.name),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : null,
    );
  }
}

String chatHubAvatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

String chatHubFormatInboxTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inDays == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (now.difference(local).inDays < 7) {
    const days = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    return days[local.weekday - 1];
  }
  return '${local.day}.${local.month}';
}

class ChannelInboxTile extends StatefulWidget {
  const ChannelInboxTile({
    super.key,
    required this.channel,
    required this.onSortAtChanged,
    required this.onTap,
    required this.onMarkedSeen,
    this.onLongPress,
  });

  final Channel channel;
  final ValueChanged<DateTime> onSortAtChanged;
  final VoidCallback onTap;
  final VoidCallback onMarkedSeen;
  final VoidCallback? onLongPress;

  @override
  State<ChannelInboxTile> createState() => _ChannelInboxTileState();
}

class _ChannelInboxTileState extends State<ChannelInboxTile> {
  String? _preview;
  DateTime? _lastPostAt;
  bool _loadingPost = false;
  late int _seenPostsCount;

  Channel get _channel => widget.channel;

  int get _newPostsCount {
    final delta = _channel.postsCount - _seenPostsCount;
    return delta > 0 ? delta : 0;
  }

  @override
  void initState() {
    super.initState();
    _seenPostsCount = _channel.seenPostsCount ?? 0;
    _preview = _channel.lastPostPreview;
    _lastPostAt = _channel.lastPostAt;
    if (_lastPostAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSortAtChanged(_lastPostAt!);
      });
    } else if (!kIsWeb) {
      _loadLastPostFallback();
    }
  }

  @override
  void didUpdateWidget(covariant ChannelInboxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _seenPostsCount = _channel.seenPostsCount ?? 0;
      _preview = _channel.lastPostPreview;
      _lastPostAt = _channel.lastPostAt;
    } else {
      final serverSeen = _channel.seenPostsCount;
      if (serverSeen != null && serverSeen > _seenPostsCount) {
        _seenPostsCount = serverSeen;
      }
    }
  }

  Future<void> _markAsSeen() async {
    final latestCount = _channel.postsCount;
    if (latestCount <= _seenPostsCount) return;
    setState(() => _seenPostsCount = latestCount);
    try {
      final seen = await ChannelService.markChannelInboxRead(_channel.id);
      if (!mounted) return;
      setState(() => _seenPostsCount = seen);
      widget.onMarkedSeen();
    } catch (_) {}
  }

  Future<void> _loadLastPostFallback() async {
    if (_loadingPost || !_channel.canLoadPostsPreview || _channel.postsCount == 0) {
      return;
    }
    setState(() => _loadingPost = true);
    try {
      final response = await ChannelService.getChannelPosts(
        channelId: _channel.id,
        limit: 1,
        offset: 0,
      );
      if (response.posts.isEmpty || !mounted) return;
      final post = response.posts.first;
      final createdAt = DateTime.tryParse(
        post['created_at']?.toString() ?? '',
      )?.toLocal();
      setState(() {
        _preview = _postPreview(post);
        _lastPostAt = createdAt;
      });
      if (createdAt != null) {
        widget.onSortAtChanged(createdAt);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPost = false);
    }
  }

  String _postPreview(Map<String, dynamic> post) {
    final title = (post['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;
    final description = (post['description'] as String?)?.trim();
    if (description != null && description.isNotEmpty) return description;
    final type = (post['type'] as String?)?.toLowerCase() ?? '';
    if (type == 'recipe') return 'Рецепт';
    if (type == 'reel' || type == 'video') return 'Видео';
    if (type == 'photo' || type == 'image') return 'Фото';
    return 'Новый пост';
  }

  String _subtitle() {
    if (_channel.postsCount > 0 && _loadingPost) return 'Загрузка…';
    if (_preview != null) return _preview!;
    final d = _channel.description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return 'Канал';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = _newPostsCount > 0;

    return ListTile(
      onTap: () async {
        await _markAsSeen();
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      leading: ChatHubChannelAvatar(channel: _channel),
      title: Row(
        children: [
          Icon(Icons.campaign_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            chatHubFormatInboxTime(_lastPostAt ?? _channel.createdAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: scheme.primary,
              child: Text(
                _newPostsCount > 9 ? '9+' : '$_newPostsCount',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
