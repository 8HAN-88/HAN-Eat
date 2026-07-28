import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/channel_service.dart';
import '../../../../widgets/app_avatar.dart';
import '../../../../widgets/telegram_ui.dart';
import 'chat_contact_bubble.dart';
import 'chat_location_bubble.dart';

class ChatHubTile extends StatelessWidget {
  const ChatHubTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
    this.draftText,
    this.draftHasReply = false,
    this.typingLabel,
  });

  final ChatConversation chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  /// Local composer draft (Telegram hub: red "Черновик: …").
  final String? draftText;
  /// Draft includes an in-progress reply target.
  final bool draftHasReply;
  /// Live typing preview from user SSE (`chat.typing`).
  final String? typingLabel;

  String _bodyPreview(ChatMessage? msg) =>
      chatHubBodyPreview(msg, isSaved: chat.isSaved);

  String? _previewPrefix(ChatMessage? msg, {required bool hasDraft}) {
    if (hasDraft) return null;
    if (msg == null) return null;
    if (msg.isMine) return 'Вы: ';
    if (chat.isGroup && (msg.senderName?.isNotEmpty ?? false)) {
      return '${msg.senderName}: ';
    }
    return null;
  }

  IconData? _mediaIcon(ChatMessage? msg) {
    if (msg == null) return null;
    switch (msg.type) {
      case 'voice':
        return Icons.mic_rounded;
      case 'image':
        return Icons.photo_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'video_note':
        return Icons.circle_outlined;
      case 'sticker':
        return Icons.emoji_emotions_outlined;
      case 'location':
        return Icons.location_on_rounded;
      case 'file':
        return Icons.insert_drive_file_outlined;
      case 'poll':
        return Icons.poll_outlined;
      default:
        if (ChatLocationPayload.tryParse(msg.content) != null) {
          return Icons.location_on_rounded;
        }
        if (ChatContactPayload.tryParse(msg.content) != null) {
          return Icons.person_rounded;
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = chat.lastMessage;
    final hasUnread = chat.unreadCount > 0 ||
        chat.unreadMentionsCount > 0 ||
        chat.unreadReactionsCount > 0;
    final hasStateIcons = chat.pinned || chat.muted;
    final draft = draftText?.trim();
    final typing = typingLabel?.trim();
    final hasTyping = typing != null && typing.isNotEmpty;
    final hasDraft = !hasTyping && draft != null && draft.isNotEmpty;
    final prefix =
        hasTyping ? null : _previewPrefix(last, hasDraft: hasDraft);
    final String body;
    if (hasTyping) {
      body = typing;
    } else if (hasDraft) {
      body = draft;
    } else {
      body = _bodyPreview(last);
    }
    final mediaIcon =
        (hasTyping || hasDraft) ? null : _mediaIcon(last);
    final showOutgoingTicks = !hasTyping &&
        !hasDraft &&
        last != null &&
        last.isMine &&
        !chat.isSaved;

    // Telegram-style flat row (no card chrome).
    return Material(
      color: hasUnread
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
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
                  : chat.isGroup
                      ? ChatHubGroupAvatar(
                          members: chat.membersPreview,
                          avatarUrl: chat.avatarUrl,
                        )
                      : ChatHubUserAvatar(
                          user: chat.peer ??
                              const ChatUserBrief(id: 0, name: 'Чат'),
                        ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (showOutgoingTicks) ...[
                          Icon(
                            last.isRead || last.isDelivered
                                ? Icons.done_all
                                : Icons.done,
                            size: 15,
                            color: last.isRead
                                ? scheme.primary
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 3),
                        ],
                        if (hasStateIcons) ...[
                          if (chat.pinned) ...[
                            Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: scheme.primary.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 3),
                          ],
                          if (chat.muted) ...[
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                        Text(
                          chatHubFormatInboxTime(chat.updatedAt),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (hasDraft) ...[
                                Text(
                                  draftHasReply ? 'Ответ: ' : 'Черновик: ',
                                  style: TextStyle(
                                    color: scheme.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ] else if (prefix != null)
                                Text(
                                  prefix,
                                  style: TextStyle(
                                    color: hasUnread
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              if (mediaIcon != null) ...[
                                Icon(
                                  mediaIcon,
                                  size: 15,
                                  color: hasUnread
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                              ],
                              Expanded(
                                child: hasTyping
                                    ? Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              body,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: scheme.primary,
                                                fontSize: 14,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          TelegramTypingDots(
                                            color: scheme.primary,
                                            size: 3.0,
                                          ),
                                        ],
                                      )
                                    : Text(
                                        body,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: hasDraft
                                              ? scheme.error
                                              : (hasUnread
                                                  ? scheme.onSurface
                                                  : scheme.onSurfaceVariant),
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          TelegramUnreadBadge(
                            count: chat.unreadCount > 0
                                ? chat.unreadCount
                                : (chat.unreadMentionsCount > 0
                                    ? chat.unreadMentionsCount
                                    : chat.unreadReactionsCount),
                            muted: chat.muted,
                            hasMention: chat.unreadMentionsCount > 0,
                            hasReaction: chat.unreadMentionsCount <= 0 &&
                                chat.unreadReactionsCount > 0,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telegram-style sticky «Архив» row above the inbox list.
class ChatHubArchiveRow extends StatelessWidget {
  const ChatHubArchiveRow({
    super.key,
    required this.count,
    required this.unread,
    this.preview,
    required this.onTap,
  });

  final int count;
  final int unread;
  final String? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = preview?.trim().isNotEmpty == true
        ? preview!.trim()
        : (count == 1 ? '1 чат' : '$count чатов');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.archive_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Архив',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            unread > 0 ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread > 0
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                TelegramUnreadBadge(count: unread),
              ] else
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
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
  const ChatHubGroupAvatar({
    super.key,
    required this.members,
    this.avatarUrl,
  });

  final List<ChatUserBrief> members;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = resolvedAvatarImage(avatarUrl, decodeWidth: 96);
    if (background != null) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: background,
      );
    }
    if (members.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.groups_rounded, color: scheme.onPrimaryContainer),
      );
    }
    return CircleAvatar(
      radius: 28,
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
    final background = resolvedAvatarImage(user.avatarUrl, decodeWidth: 96);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: background,
          child: background == null
              ? Text(
                  chatHubAvatarLetter(user.displayName),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : null,
        ),
        if (user.isOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 13,
              height: 13,
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
    final background = resolvedAvatarImage(channel.avatarUrl, decodeWidth: 96);
    return CircleAvatar(
      radius: 28,
      backgroundImage: background,
      child: background == null
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

String chatHubBodyPreview(ChatMessage? msg, {bool isSaved = false}) {
  if (msg == null) {
    return isSaved ? 'Сохраняйте сообщения и заметки' : 'Нет сообщений';
  }
  if (msg.type == 'voice') return 'Голосовое сообщение';
  if (msg.type == 'poll') {
    final poll = msg.poll;
    if (poll != null) return chatPollPreviewText(poll);
    return 'Опрос';
  }
  if (msg.type == 'image') return 'Фото';
  if (msg.type == 'video') return 'Видео';
  if (msg.type == 'video_note') return 'Видеосообщение';
  if (msg.type == 'sticker') return 'Стикер';
  if (msg.type == 'location' ||
      ChatLocationPayload.tryParse(msg.content) != null) {
    return 'Геопозиция';
  }
  if (msg.type == 'file') {
    final name = msg.content.trim();
    return name.isEmpty ? 'Файл' : name;
  }
  final contact = ChatContactPayload.tryParse(msg.content);
  if (contact != null) return contact.displayName;
  final content = msg.content.trim();
  return content.isEmpty ? 'Сообщение' : content;
}

String chatHubFormatInboxTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inDays == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}

class ChannelInboxTile extends StatefulWidget {
  const ChannelInboxTile({
    super.key,
    required this.channel,
    required this.onSortAtChanged,
    required this.onTap,
    required this.onMarkedSeen,
    this.onLongPress,
    this.muted = false,
    this.isFavorite = false,
  });

  final Channel channel;
  final ValueChanged<DateTime> onSortAtChanged;
  final VoidCallback onTap;
  final VoidCallback onMarkedSeen;
  final VoidCallback? onLongPress;
  final bool muted;
  final bool isFavorite;

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
    if (_loadingPost ||
        !_channel.canLoadPostsPreview ||
        _channel.postsCount == 0) {
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

    return Material(
      color: hasUnread
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: () async {
          await _markAsSeen();
          widget.onTap();
        },
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ChatHubChannelAvatar(channel: _channel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.campaign_outlined,
                            size: 15, color: scheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (widget.isFavorite) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: scheme.primary.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 3),
                        ],
                        if (widget.muted) ...[
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          chatHubFormatInboxTime(
                              _lastPostAt ?? _channel.createdAt),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _subtitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          TelegramUnreadBadge(
                            count: _newPostsCount,
                            muted: widget.muted,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
