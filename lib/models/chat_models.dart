import 'chat_poll.dart';

export 'chat_poll.dart'
    show
        ChatPollMessage,
        ChatPollSettings,
        ChatPollVoter,
        ChatPollVotersOption,
        ChatPollVotersResult,
        parseChatPollFromContent,
        chatPollPreviewText,
        patchChatPollClosedInContent,
        applyOptimisticPollVoteToContent,
        applyOptimisticPollOptionToContent;

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
  }
  return DateTime.now();
}

class ChatUserBrief {
  const ChatUserBrief({
    required this.id,
    this.name,
    this.username,
    this.avatarUrl,
    this.lastSeenAt,
    this.isBot = false,
    this.isGroupAdmin = false,
    this.isGroupCreator = false,
    this.canManageMembers = false,
    this.canManagePostingPermissions = false,
    this.canChangeInfo = false,
    this.canDeleteMessages = false,
    this.canPinMessages = false,
    this.canInviteUsers = false,
    this.canManageVideoChats = false,
    this.sendRestricted = false,
    this.sendRestrictedUntil,
    this.sendRestrictionReason,
    this.paidMessageStars = 0,
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final DateTime? lastSeenAt;
  final bool isBot;
  final bool isGroupAdmin;
  final bool isGroupCreator;
  final bool canManageMembers;
  final bool canManagePostingPermissions;
  final bool canChangeInfo;
  final bool canDeleteMessages;
  final bool canPinMessages;
  final bool canInviteUsers;
  final bool canManageVideoChats;
  final bool sendRestricted;
  final DateTime? sendRestrictedUntil;
  final String? sendRestrictionReason;
  final int paidMessageStars;

  bool get isOnline {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen.toLocal()).inMinutes < 3;
  }

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return u.startsWith('@') ? u : '@$u';
    return 'Пользователь';
  }

  factory ChatUserBrief.fromJson(Map<String, dynamic> json) {
    DateTime? lastSeen;
    final raw = json['last_seen_at'];
    if (raw is String && raw.isNotEmpty) {
      lastSeen = DateTime.tryParse(raw);
    }
    return ChatUserBrief(
      id: _parseInt(json['id']),
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      lastSeenAt: lastSeen,
      isBot: json['is_bot'] as bool? ?? false,
      isGroupAdmin: json['is_group_admin'] as bool? ?? false,
      isGroupCreator: json['is_group_creator'] as bool? ?? false,
      canManageMembers: json['can_manage_members'] as bool? ?? false,
      canManagePostingPermissions:
          json['can_manage_posting_permissions'] as bool? ?? false,
      canChangeInfo: json['can_change_info'] as bool? ?? false,
      canDeleteMessages: json['can_delete_messages'] as bool? ?? false,
      canPinMessages: json['can_pin_messages'] as bool? ?? false,
      canInviteUsers: json['can_invite_users'] as bool? ?? false,
      canManageVideoChats: json['can_manage_video_chats'] as bool? ?? false,
      sendRestricted: json['send_restricted'] as bool? ?? false,
      sendRestrictedUntil: json['send_restricted_until'] is String
          ? DateTime.tryParse(json['send_restricted_until'] as String)
          : null,
      sendRestrictionReason: json['send_restriction_reason'] as String?,
      paidMessageStars: _parseInt(json['paid_message_stars']),
    );
  }

  ChatUserBrief copyWith({
    String? name,
    String? username,
    String? avatarUrl,
    DateTime? lastSeenAt,
    bool clearLastSeenAt = false,
    int? paidMessageStars,
  }) {
    return ChatUserBrief(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastSeenAt: clearLastSeenAt ? null : (lastSeenAt ?? this.lastSeenAt),
      isBot: isBot,
      isGroupAdmin: isGroupAdmin,
      isGroupCreator: isGroupCreator,
      canManageMembers: canManageMembers,
      canManagePostingPermissions: canManagePostingPermissions,
      canChangeInfo: canChangeInfo,
      canDeleteMessages: canDeleteMessages,
      canPinMessages: canPinMessages,
      canInviteUsers: canInviteUsers,
      canManageVideoChats: canManageVideoChats,
      sendRestricted: sendRestricted,
      sendRestrictedUntil: sendRestrictedUntil,
      sendRestrictionReason: sendRestrictionReason,
      paidMessageStars: paidMessageStars ?? this.paidMessageStars,
    );
  }
}

class ChatBotCommand {
  const ChatBotCommand({
    required this.command,
    this.description = '',
  });

  final String command;
  final String description;

  factory ChatBotCommand.fromJson(Map<String, dynamic> json) {
    return ChatBotCommand(
      command: (json['command'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
    );
  }
}

class ChatReactionSummary {
  const ChatReactionSummary({
    required this.emoji,
    required this.count,
    this.reactedByMe = false,
    this.starsTotal = 0,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;
  final int starsTotal;

  factory ChatReactionSummary.fromJson(Map<String, dynamic> json) {
    return ChatReactionSummary(
      emoji: json['emoji'] as String? ?? '',
      count: _parseInt(json['count']),
      reactedByMe: json['reacted_by_me'] as bool? ?? false,
      starsTotal: _parseInt(json['stars_total']),
    );
  }
}

class ChatInlineKeyboardButton {
  const ChatInlineKeyboardButton({
    required this.text,
    this.callbackData,
    this.url,
    this.callbackText,
    this.miniAppId,
  });

  final String text;
  final String? callbackData;
  final String? url;
  final String? callbackText;
  final int? miniAppId;

  bool get isWebApp => miniAppId != null && miniAppId! > 0;

  factory ChatInlineKeyboardButton.fromJson(Map<String, dynamic> json) {
    int? miniAppId = (json['miniapp_id'] as num?)?.toInt();
    final webApp = json['web_app'];
    if (miniAppId == null && webApp is Map) {
      final raw = webApp['miniapp_id'] ?? webApp['id'];
      if (raw is num) miniAppId = raw.toInt();
      if (raw is String) miniAppId = int.tryParse(raw);
    }
    return ChatInlineKeyboardButton(
      text: json['text'] as String? ?? '',
      callbackData: json['callback_data'] as String?,
      url: json['url'] as String?,
      callbackText: json['callback_text'] as String?,
      miniAppId: miniAppId,
    );
  }
}

/// Bot ReplyKeyboard (above composer), Telegram-like.
class ChatReplyKeyboard {
  const ChatReplyKeyboard({
    this.rows = const [],
    this.oneTime = false,
    this.resize = true,
    this.placeholder,
    this.remove = false,
  });

  final List<List<String>> rows;
  final bool oneTime;
  final bool resize;
  final String? placeholder;
  final bool remove;

  bool get isEmpty => rows.isEmpty;

  static ChatReplyKeyboard? tryParse(Map<String, dynamic> json) {
    final remove = json['remove_reply_keyboard'] as bool? ?? false;
    final raw = json['reply_keyboard'];
    if (remove && raw == null) {
      return const ChatReplyKeyboard(remove: true);
    }
    if (raw is! List) return null;
    final rows = <List<String>>[];
    for (final rowRaw in raw) {
      if (rowRaw is! List) continue;
      final row = <String>[];
      for (final btn in rowRaw) {
        if (btn is Map && btn['text'] is String) {
          final t = (btn['text'] as String).trim();
          if (t.isNotEmpty) row.add(t);
        } else if (btn is String && btn.trim().isNotEmpty) {
          row.add(btn.trim());
        }
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isEmpty && !remove) return null;
    return ChatReplyKeyboard(
      rows: rows,
      oneTime: json['reply_keyboard_one_time'] as bool? ?? false,
      resize: json['reply_keyboard_resize'] as bool? ?? true,
      placeholder: json['reply_keyboard_placeholder'] as String?,
      remove: remove,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderName,
    required this.type,
    required this.content,
    this.mediaUrl,
    this.replyToMessageId,
    this.forwardFromUserId,
    this.forwardFromName,
    this.forwardedFromMessageId,
    this.forwardedFromConversationId,
    required this.createdAt,
    this.editedAt,
    this.isMine = false,
    this.isDelivered = false,
    this.isRead = false,
    this.readCount = 0,
    this.disableWebpagePreview = false,
    this.mediaGroupId,
    this.hasSpoiler = false,
    this.isPaid = false,
    this.priceStars = 0,
    this.purchased = true,
    this.reactions = const [],
    this.inlineKeyboard = const [],
    this.replyKeyboard,
    this.effectId,
    this.topicId,
    this.isAnonymous = false,
    this.clientMessageId,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String? senderName;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? replyToMessageId;
  final int? forwardFromUserId;
  final String? forwardFromName;
  final int? forwardedFromMessageId;
  final int? forwardedFromConversationId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isMine;
  /// Peer device received the message (Telegram gray ✓✓).
  final bool isDelivered;
  final bool isRead;
  /// Group: other members who have read up to this message (outgoing only).
  final int readCount;
  final bool disableWebpagePreview;
  /// Shared id for multi-photo/video albums.
  final String? mediaGroupId;
  /// Telegram media spoiler — blur until tapped.
  final bool hasSpoiler;
  final bool isPaid;
  final int priceStars;
  final bool purchased;
  final List<ChatReactionSummary> reactions;
  final List<List<ChatInlineKeyboardButton>> inlineKeyboard;
  /// Present on bot replies that set/clear ReplyKeyboard for the peer.
  final ChatReplyKeyboard? replyKeyboard;
  /// Telegram-like send effect id (confetti, hearts, …).
  final String? effectId;
  /// Forum topic id (null = General / pre-forum).
  final int? topicId;
  /// Group admin posted as the group (Telegram anonymous admin).
  final bool isAnonymous;
  /// Client idempotency key — matches optimistic bubble to the server row.
  final String? clientMessageId;

  bool get isLockedPaidMedia =>
      isPaid && !purchased && !isMine && priceStars > 0;

  bool get isForwarded =>
      forwardFromUserId != null ||
      (forwardFromName != null && forwardFromName!.trim().isNotEmpty);

  bool get isEdited => editedAt != null;

  ChatPollMessage? get poll =>
      type == 'poll' ? parseChatPollFromContent(content) : null;

  int? get voiceDurationSec {
    if (type != 'voice' && type != 'video_note') return null;
    return int.tryParse(content.trim());
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? editedAt;
    final editedRaw = json['edited_at'];
    if (editedRaw is String && editedRaw.isNotEmpty) {
      editedAt = DateTime.tryParse(editedRaw);
    }
    final reactionsRaw = json['reactions'] as List<dynamic>? ?? [];
    final reactions = <ChatReactionSummary>[];
    for (final raw in reactionsRaw) {
      if (raw is Map<String, dynamic>) {
        try {
          reactions.add(ChatReactionSummary.fromJson(raw));
        } catch (_) {}
      }
    }
    final keyboardRaw = json['inline_keyboard'] as List<dynamic>? ?? const [];
    final keyboard = <List<ChatInlineKeyboardButton>>[];
    for (final rowRaw in keyboardRaw) {
      if (rowRaw is! List) continue;
      final row = <ChatInlineKeyboardButton>[];
      for (final item in rowRaw) {
        if (item is Map<String, dynamic>) {
          row.add(ChatInlineKeyboardButton.fromJson(item));
        }
      }
      if (row.isNotEmpty) keyboard.add(row);
    }
    return ChatMessage(
      id: _parseInt(json['id']),
      conversationId: _parseInt(json['conversation_id']),
      senderId: _parseInt(json['sender_id']),
      senderName: json['sender_name'] as String?,
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      replyToMessageId: json['reply_to_message_id'] != null
          ? _parseInt(json['reply_to_message_id'])
          : null,
      forwardFromUserId: json['forward_from_user_id'] != null
          ? _parseInt(json['forward_from_user_id'])
          : null,
      forwardFromName: json['forward_from_name'] as String?,
      forwardedFromMessageId: json['forwarded_from_message_id'] != null
          ? _parseInt(json['forwarded_from_message_id'])
          : null,
      forwardedFromConversationId:
          json['forwarded_from_conversation_id'] != null
              ? _parseInt(json['forwarded_from_conversation_id'])
              : null,
      createdAt: _parseDate(json['created_at']),
      editedAt: editedAt,
      isMine: json['is_mine'] as bool? ?? false,
      isDelivered: json['is_delivered'] as bool? ??
          (json['is_read'] as bool? ?? false),
      isRead: json['is_read'] as bool? ?? false,
      readCount: _parseInt(json['read_count']),
      disableWebpagePreview:
          json['disable_webpage_preview'] as bool? ?? false,
      mediaGroupId: (json['media_group_id'] as String?)?.trim().isEmpty == true
          ? null
          : (json['media_group_id'] as String?)?.trim(),
      hasSpoiler: json['has_spoiler'] as bool? ?? false,
      isPaid: json['is_paid'] as bool? ?? false,
      priceStars: _parseInt(json['price_stars']),
      purchased: json['purchased'] as bool? ??
          !(json['is_paid'] as bool? ?? false),
      reactions: reactions,
      inlineKeyboard: keyboard,
      replyKeyboard: ChatReplyKeyboard.tryParse(json),
      effectId: (json['effect_id'] as String?)?.trim().isEmpty == true
          ? null
          : (json['effect_id'] as String?)?.trim(),
      topicId: json['topic_id'] != null ? _parseInt(json['topic_id']) : null,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      clientMessageId: (json['client_message_id'] as String?)?.trim().isEmpty ==
              true
          ? null
          : (json['client_message_id'] as String?)?.trim(),
    );
  }

  ChatMessage copyWith({
    bool? isDelivered,
    bool? isRead,
    int? readCount,
    bool? disableWebpagePreview,
    String? mediaGroupId,
    bool? hasSpoiler,
    String? content,
    String? mediaUrl,
    DateTime? editedAt,
    bool? isPaid,
    int? priceStars,
    bool? purchased,
    List<ChatReactionSummary>? reactions,
    List<List<ChatInlineKeyboardButton>>? inlineKeyboard,
    ChatReplyKeyboard? replyKeyboard,
    String? effectId,
    int? topicId,
    bool? isAnonymous,
    String? clientMessageId,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      type: type,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      replyToMessageId: replyToMessageId,
      forwardFromUserId: forwardFromUserId,
      forwardFromName: forwardFromName,
      forwardedFromMessageId: forwardedFromMessageId,
      forwardedFromConversationId: forwardedFromConversationId,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      isMine: isMine,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      readCount: readCount ?? this.readCount,
      disableWebpagePreview:
          disableWebpagePreview ?? this.disableWebpagePreview,
      mediaGroupId: mediaGroupId ?? this.mediaGroupId,
      hasSpoiler: hasSpoiler ?? this.hasSpoiler,
      isPaid: isPaid ?? this.isPaid,
      priceStars: priceStars ?? this.priceStars,
      purchased: purchased ?? this.purchased,
      reactions: reactions ?? this.reactions,
      inlineKeyboard: inlineKeyboard ?? this.inlineKeyboard,
      replyKeyboard: replyKeyboard ?? this.replyKeyboard,
      effectId: effectId ?? this.effectId,
      topicId: topicId ?? this.topicId,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      clientMessageId: clientMessageId ?? this.clientMessageId,
    );
  }
}

class ChatMessageReadersResult {
  const ChatMessageReadersResult({
    required this.readers,
    this.readerCount = 0,
    this.otherMemberCount = 0,
  });

  final List<ChatUserBrief> readers;
  final int readerCount;
  final int otherMemberCount;
}

class ChatMessageReactionUser {
  const ChatMessageReactionUser({
    required this.emoji,
    required this.user,
    this.starsAmount = 0,
  });

  final String emoji;
  final ChatUserBrief user;
  final int starsAmount;
}

class ChatMessageReactionsResult {
  const ChatMessageReactionsResult({
    required this.items,
    this.reactionCount = 0,
  });

  final List<ChatMessageReactionUser> items;
  final int reactionCount;
}

/// Не затирает локально закрытый опрос / купленное медиа устаревшим fanout.
ChatMessage applyIncomingChatMessagePreservingLocalPoll(
  ChatMessage local,
  ChatMessage incoming,
) {
  var next = incoming;
  if (local.type == 'poll' && incoming.type == 'poll') {
    final localPoll = local.poll;
    final incomingPoll = incoming.poll;
    if (localPoll != null &&
        incomingPoll != null &&
        localPoll.isClosed &&
        !incomingPoll.isClosed) {
      next = next.copyWith(
        content: patchChatPollClosedInContent(incoming.content, isClosed: true),
      );
    }
  }
  // WS/edit fanout redacts paid media; keep unlock + URL the user already paid for.
  if (local.isPaid &&
      local.purchased &&
      !local.isMine &&
      (next.mediaUrl == null || next.mediaUrl!.isEmpty) &&
      local.mediaUrl != null &&
      local.mediaUrl!.isNotEmpty) {
    next = next.copyWith(
      mediaUrl: local.mediaUrl,
      purchased: true,
      isPaid: true,
      priceStars: local.priceStars > 0 ? local.priceStars : next.priceStars,
    );
  } else if (local.isPaid && local.purchased && !next.purchased) {
    next = next.copyWith(purchased: true, isPaid: true);
  }
  return next;
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.type,
    this.peer,
    this.title,
    this.avatarUrl,
    this.memberCount = 0,
    this.pendingJoinRequestsCount = 0,
    this.membersPreview = const [],
    this.lastMessage,
    this.unreadCount = 0,
    this.unreadMentionsCount = 0,
    this.unreadReactionsCount = 0,
    required this.updatedAt,
    this.pinned = false,
    this.archived = false,
    this.muted = false,
    this.mutedUntil,
    this.notifyMode = 'all',
    this.wallpaperStyle,
    this.wallpaperUrl,
    this.bubbleAccent,
    this.createdByUserId,
    this.onlyAdminsCanPost = false,
    this.joinByRequestEnabled = false,
    this.slowModeSeconds = 0,
    this.antiFloodMaxMessagesPerMinute = 0,
    this.protectContent = false,
    this.autoDeleteSeconds = 0,
    this.isForum = false,
    this.amIGroupAdmin = false,
    this.amICanManageMembers = false,
    this.amICanManagePostingPermissions = false,
    this.amICanChangeInfo = false,
    this.amICanDeleteMessages = false,
    this.amICanPinMessages = false,
    this.amICanInviteUsers = false,
    this.amICanManageVideoChats = false,
    this.amISendRestricted = false,
    this.amISendRestrictedUntil,
    this.amISendRestrictionReason,
    this.peerBlockedByMe = false,
    this.replyKeyboard,
  });

  final int id;
  final String type;
  final ChatUserBrief? peer;
  final String? title;
  final String? avatarUrl;
  final int memberCount;
  final int pendingJoinRequestsCount;
  final List<ChatUserBrief> membersPreview;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  final DateTime updatedAt;
  final bool pinned;
  final bool archived;
  final bool muted;
  final DateTime? mutedUntil;
  /// all | mentions | none
  final String notifyMode;
  final String? wallpaperStyle;
  final String? wallpaperUrl;
  final String? bubbleAccent;
  final int? createdByUserId;
  final bool onlyAdminsCanPost;
  final bool joinByRequestEnabled;
  final int slowModeSeconds;
  final int antiFloodMaxMessagesPerMinute;
  final bool protectContent;
  final int autoDeleteSeconds;
  /// Telegram-like Topics / Forum mode for groups.
  final bool isForum;
  final bool amIGroupAdmin;
  final bool amICanManageMembers;
  final bool amICanManagePostingPermissions;
  final bool amICanChangeInfo;
  final bool amICanDeleteMessages;
  final bool amICanPinMessages;
  final bool amICanInviteUsers;
  final bool amICanManageVideoChats;
  final bool amISendRestricted;
  final DateTime? amISendRestrictedUntil;
  final String? amISendRestrictionReason;
  final bool peerBlockedByMe;
  final ChatReplyKeyboard? replyKeyboard;

  bool get isGroup => type == 'group';

  bool get isSaved => type == 'saved';

  String get displayTitle {
    if (isSaved) return 'Избранное';
    if (isGroup) {
      final t = title?.trim();
      if (t != null && t.isNotEmpty) return t;
      return 'Группа';
    }
    return peer?.displayName ?? 'Чат';
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final convType = json['type'] as String? ?? 'direct';
    ChatUserBrief? peer;
    final peerJson = json['peer'];
    if (peerJson is Map<String, dynamic>) {
      peer = ChatUserBrief.fromJson(peerJson);
    }
    if (peer == null && convType == 'direct') {
      throw FormatException('ChatConversation: missing peer');
    }
    final previewRaw = json['members_preview'] as List<dynamic>? ?? [];
    final preview = <ChatUserBrief>[];
    for (final raw in previewRaw) {
      if (raw is Map<String, dynamic>) {
        try {
          preview.add(ChatUserBrief.fromJson(raw));
        } catch (_) {}
      }
    }
    ChatMessage? lastMessage;
    final lastRaw = json['last_message'];
    if (lastRaw is Map<String, dynamic>) {
      try {
        lastMessage = ChatMessage.fromJson(lastRaw);
      } catch (_) {}
    }
    return ChatConversation(
      id: _parseInt(json['id']),
      type: convType,
      peer: peer,
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: _parseInt(json['member_count']),
      pendingJoinRequestsCount: _parseInt(json['pending_join_requests_count']),
      membersPreview: preview,
      lastMessage: lastMessage,
      unreadCount: _parseInt(json['unread_count']),
      unreadMentionsCount: _parseInt(json['unread_mentions_count']),
      unreadReactionsCount: _parseInt(json['unread_reactions_count']),
      updatedAt: _parseDate(json['updated_at']),
      pinned: json['pinned'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      mutedUntil: json['muted_until'] is String
          ? DateTime.tryParse(json['muted_until'] as String)
          : null,
      notifyMode: () {
        final raw = (json['notify_mode'] as String?)?.trim().toLowerCase();
        if (raw == 'mentions' || raw == 'none' || raw == 'all') return raw!;
        return (json['muted'] as bool? ?? false) ? 'mentions' : 'all';
      }(),
      wallpaperStyle: (json['wallpaper_style'] as String?)?.trim(),
      wallpaperUrl: () {
        final raw = json['wallpaper_url'];
        if (raw is String) {
          final t = raw.trim();
          return t.isEmpty ? null : t;
        }
        return null;
      }(),
      bubbleAccent: (json['bubble_accent'] as String?)?.trim(),
      createdByUserId: json['created_by_user_id'] != null
          ? _parseInt(json['created_by_user_id'])
          : null,
      onlyAdminsCanPost: json['only_admins_can_post'] as bool? ?? false,
      joinByRequestEnabled: json['join_by_request_enabled'] as bool? ?? false,
      slowModeSeconds: _parseInt(json['slow_mode_seconds']),
      antiFloodMaxMessagesPerMinute:
          _parseInt(json['anti_flood_max_messages_per_minute']),
      protectContent: json['protect_content'] as bool? ?? false,
      autoDeleteSeconds: _parseInt(json['auto_delete_seconds']),
      isForum: json['is_forum'] as bool? ?? false,
      amIGroupAdmin: json['am_i_group_admin'] as bool? ?? false,
      amICanManageMembers: json['am_i_can_manage_members'] as bool? ?? false,
      amICanManagePostingPermissions:
          json['am_i_can_manage_posting_permissions'] as bool? ?? false,
      amICanChangeInfo: json['am_i_can_change_info'] as bool? ?? false,
      amICanDeleteMessages: json['am_i_can_delete_messages'] as bool? ?? false,
      amICanPinMessages: json['am_i_can_pin_messages'] as bool? ?? false,
      amICanInviteUsers: json['am_i_can_invite_users'] as bool? ?? false,
      amICanManageVideoChats:
          json['am_i_can_manage_video_chats'] as bool? ?? false,
      amISendRestricted: json['am_i_send_restricted'] as bool? ?? false,
      amISendRestrictedUntil: json['am_i_send_restricted_until'] is String
          ? DateTime.tryParse(json['am_i_send_restricted_until'] as String)
          : null,
      amISendRestrictionReason: json['am_i_send_restriction_reason'] as String?,
      peerBlockedByMe: json['peer_blocked_by_me'] as bool? ?? false,
      replyKeyboard: ChatReplyKeyboard.tryParse(json),
    );
  }

  ChatConversation copyWith({
    String? title,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    int? memberCount,
    int? pendingJoinRequestsCount,
    List<ChatUserBrief>? membersPreview,
    ChatUserBrief? peer,
    int? unreadCount,
    int? unreadMentionsCount,
    int? unreadReactionsCount,
    bool? muted,
    DateTime? mutedUntil,
    bool clearMutedUntil = false,
    String? notifyMode,
    String? wallpaperStyle,
    bool clearWallpaperStyle = false,
    String? wallpaperUrl,
    bool clearWallpaperUrl = false,
    String? bubbleAccent,
    bool clearBubbleAccent = false,
    bool? pinned,
    bool? archived,
    bool? onlyAdminsCanPost,
    bool? joinByRequestEnabled,
    int? slowModeSeconds,
    int? antiFloodMaxMessagesPerMinute,
    bool? protectContent,
    int? autoDeleteSeconds,
    bool? isForum,
    bool? amIGroupAdmin,
    bool? amICanManageMembers,
    bool? amICanManagePostingPermissions,
    bool? amICanChangeInfo,
    bool? amICanDeleteMessages,
    bool? amICanPinMessages,
    bool? amICanInviteUsers,
    bool? amICanManageVideoChats,
    bool? amISendRestricted,
    DateTime? amISendRestrictedUntil,
    String? amISendRestrictionReason,
    bool? peerBlockedByMe,
    ChatReplyKeyboard? replyKeyboard,
    bool clearReplyKeyboard = false,
    ChatMessage? lastMessage,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id,
      type: type,
      peer: peer ?? this.peer,
      title: title ?? this.title,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      memberCount: memberCount ?? this.memberCount,
      pendingJoinRequestsCount:
          pendingJoinRequestsCount ?? this.pendingJoinRequestsCount,
      membersPreview: membersPreview ?? this.membersPreview,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      unreadMentionsCount: unreadMentionsCount ?? this.unreadMentionsCount,
      unreadReactionsCount:
          unreadReactionsCount ?? this.unreadReactionsCount,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      muted: muted ?? this.muted,
      mutedUntil: clearMutedUntil
          ? null
          : (mutedUntil ?? this.mutedUntil),
      notifyMode: notifyMode ?? this.notifyMode,
      wallpaperStyle: clearWallpaperStyle
          ? null
          : (wallpaperStyle ?? this.wallpaperStyle),
      wallpaperUrl: clearWallpaperUrl
          ? null
          : (wallpaperUrl ?? this.wallpaperUrl),
      bubbleAccent: clearBubbleAccent
          ? null
          : (bubbleAccent ?? this.bubbleAccent),
      createdByUserId: createdByUserId,
      onlyAdminsCanPost: onlyAdminsCanPost ?? this.onlyAdminsCanPost,
      joinByRequestEnabled: joinByRequestEnabled ?? this.joinByRequestEnabled,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      antiFloodMaxMessagesPerMinute:
          antiFloodMaxMessagesPerMinute ?? this.antiFloodMaxMessagesPerMinute,
      protectContent: protectContent ?? this.protectContent,
      autoDeleteSeconds: autoDeleteSeconds ?? this.autoDeleteSeconds,
      isForum: isForum ?? this.isForum,
      amIGroupAdmin: amIGroupAdmin ?? this.amIGroupAdmin,
      amICanManageMembers: amICanManageMembers ?? this.amICanManageMembers,
      amICanManagePostingPermissions:
          amICanManagePostingPermissions ?? this.amICanManagePostingPermissions,
      amICanChangeInfo: amICanChangeInfo ?? this.amICanChangeInfo,
      amICanDeleteMessages:
          amICanDeleteMessages ?? this.amICanDeleteMessages,
      amICanPinMessages: amICanPinMessages ?? this.amICanPinMessages,
      amICanInviteUsers: amICanInviteUsers ?? this.amICanInviteUsers,
      amICanManageVideoChats:
          amICanManageVideoChats ?? this.amICanManageVideoChats,
      amISendRestricted: amISendRestricted ?? this.amISendRestricted,
      amISendRestrictedUntil:
          amISendRestrictedUntil ?? this.amISendRestrictedUntil,
      amISendRestrictionReason:
          amISendRestrictionReason ?? this.amISendRestrictionReason,
      peerBlockedByMe: peerBlockedByMe ?? this.peerBlockedByMe,
      replyKeyboard: clearReplyKeyboard
          ? null
          : (replyKeyboard ?? this.replyKeyboard),
    );
  }
}

class ChatContact {
  const ChatContact({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  final int id;
  final ChatUserBrief user;
  final DateTime createdAt;

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw FormatException('ChatContact: missing user');
    }
    return ChatContact(
      id: _parseInt(json['id']),
      user: ChatUserBrief.fromJson(userJson),
      createdAt: _parseDate(json['created_at']),
    );
  }
}

class ChatGroupBanEntry {
  const ChatGroupBanEntry({
    required this.user,
    required this.bannedAt,
    this.reason,
    this.bannedUntil,
  });

  final ChatUserBrief user;
  final DateTime bannedAt;
  final String? reason;
  final DateTime? bannedUntil;

  factory ChatGroupBanEntry.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw FormatException('ChatGroupBanEntry: missing user');
    }
    return ChatGroupBanEntry(
      user: ChatUserBrief.fromJson(userJson),
      bannedAt: _parseDate(json['banned_at']),
      reason: json['reason'] as String?,
      bannedUntil: json['banned_until'] is String
          ? DateTime.tryParse(json['banned_until'] as String)
          : null,
    );
  }
}

class ChatGroupInviteLink {
  const ChatGroupInviteLink({
    required this.id,
    required this.token,
    required this.inviteLink,
    required this.createdAt,
    this.expiresAt,
    this.maxUses,
    this.usesCount = 0,
    this.revokedAt,
  });

  final int id;
  final String token;
  final String inviteLink;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? maxUses;
  final int usesCount;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  bool get isExhausted => maxUses != null && usesCount >= (maxUses ?? 0);

  factory ChatGroupInviteLink.fromJson(Map<String, dynamic> json) {
    return ChatGroupInviteLink(
      id: _parseInt(json['id']),
      token: json['token'] as String? ?? '',
      inviteLink: json['invite_link'] as String? ?? '',
      createdAt: _parseDate(json['created_at']),
      expiresAt: json['expires_at'] is String
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      maxUses: json['max_uses'] != null ? _parseInt(json['max_uses']) : null,
      usesCount: _parseInt(json['uses_count']),
      revokedAt: json['revoked_at'] is String
          ? DateTime.tryParse(json['revoked_at'] as String)
          : null,
    );
  }
}

class ChatJoinByInviteResult {
  const ChatJoinByInviteResult({
    required this.status,
    this.conversation,
  });

  final String status; // joined | requested
  final ChatConversation? conversation;

  factory ChatJoinByInviteResult.fromJson(Map<String, dynamic> json) {
    final convRaw = json['conversation'];
    ChatConversation? conv;
    if (convRaw is Map<String, dynamic>) {
      conv = ChatConversation.fromJson(convRaw);
    }
    return ChatJoinByInviteResult(
      status: json['status'] as String? ?? 'joined',
      conversation: conv,
    );
  }
}

class ChatGroupJoinRequest {
  const ChatGroupJoinRequest({
    required this.id,
    required this.user,
    required this.status,
    required this.requestedAt,
  });

  final int id;
  final ChatUserBrief user;
  final String status;
  final DateTime requestedAt;

  factory ChatGroupJoinRequest.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    if (userRaw is! Map<String, dynamic>) {
      throw FormatException('ChatGroupJoinRequest: missing user');
    }
    return ChatGroupJoinRequest(
      id: _parseInt(json['id']),
      user: ChatUserBrief.fromJson(userRaw),
      status: json['status'] as String? ?? 'pending',
      requestedAt: _parseDate(json['requested_at']),
    );
  }
}

class ChatJoinRequestsInboxItem {
  const ChatJoinRequestsInboxItem({
    required this.id,
    required this.conversation,
    required this.user,
    required this.status,
    required this.requestedAt,
  });

  final int id;
  final ChatConversation conversation;
  final ChatUserBrief user;
  final String status;
  final DateTime requestedAt;

  factory ChatJoinRequestsInboxItem.fromJson(Map<String, dynamic> json) {
    final convRaw = json['conversation'];
    final userRaw = json['user'];
    if (convRaw is! Map<String, dynamic>) {
      throw FormatException('ChatJoinRequestsInboxItem: missing conversation');
    }
    if (userRaw is! Map<String, dynamic>) {
      throw FormatException('ChatJoinRequestsInboxItem: missing user');
    }
    return ChatJoinRequestsInboxItem(
      id: _parseInt(json['id']),
      conversation: ChatConversation.fromJson(convRaw),
      user: ChatUserBrief.fromJson(userRaw),
      status: json['status'] as String? ?? 'pending',
      requestedAt: _parseDate(json['requested_at']),
    );
  }
}

class ChatGroupModerationLogItem {
  const ChatGroupModerationLogItem({
    required this.id,
    required this.action,
    required this.text,
    required this.createdAt,
    this.actor,
  });

  final int id;
  final String action;
  final String text;
  final DateTime createdAt;
  final ChatUserBrief? actor;

  factory ChatGroupModerationLogItem.fromJson(Map<String, dynamic> json) {
    final actorRaw = json['actor'];
    return ChatGroupModerationLogItem(
      id: _parseInt(json['id']),
      action: json['action'] as String? ?? 'other',
      text: json['text'] as String? ?? '',
      createdAt: _parseDate(json['created_at']),
      actor: actorRaw is Map<String, dynamic>
          ? ChatUserBrief.fromJson(actorRaw)
          : null,
    );
  }
}

class ChatUserSearchItem {
  const ChatUserSearchItem({
    required this.id,
    this.name,
    this.username,
    this.avatarUrl,
    this.isContact = false,
    this.phoneHash,
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final bool isContact;
  final String? phoneHash;

  ChatUserBrief get brief => ChatUserBrief(
        id: id,
        name: name,
        username: username,
        avatarUrl: avatarUrl,
      );

  factory ChatUserSearchItem.fromJson(Map<String, dynamic> json) {
    return ChatUserSearchItem(
      id: _parseInt(json['id']),
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isContact: json['is_contact'] as bool? ?? false,
      phoneHash: json['phone_hash'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'is_contact': isContact,
        if (phoneHash != null) 'phone_hash': phoneHash,
      };
}

class ChatFolderFilters {
  const ChatFolderFilters({
    this.groups = false,
    this.channels = false,
    this.direct = false,
    this.contacts = false,
    this.nonContacts = false,
    this.bots = false,
    this.unreadOnly = false,
    this.excludeMuted = false,
    this.excludeArchived = false,
    this.excludeBots = false,
  });

  final bool groups;
  final bool channels;
  /// Private / direct chats (Telegram "Личные чаты").
  final bool direct;
  /// Direct chats with people from Contacts (not bots).
  final bool contacts;
  /// Direct chats with people not in Contacts (not bots).
  final bool nonContacts;
  /// Direct chats with bots.
  final bool bots;
  final bool unreadOnly;
  final bool excludeMuted;
  final bool excludeArchived;
  final bool excludeBots;

  bool get isEmpty =>
      !groups &&
      !channels &&
      !direct &&
      !contacts &&
      !nonContacts &&
      !bots &&
      !unreadOnly &&
      !excludeMuted &&
      !excludeArchived &&
      !excludeBots;

  bool get needsFolderFiltersPlus =>
      contacts ||
      nonContacts ||
      bots ||
      unreadOnly ||
      excludeMuted ||
      excludeArchived ||
      excludeBots;

  bool get hasTypeFilter =>
      groups || channels || direct || contacts || nonContacts || bots;

  bool get hasExcludeFilter =>
      excludeMuted || excludeArchived || excludeBots;

  ChatFolderFilters copyWith({
    bool? groups,
    bool? channels,
    bool? direct,
    bool? contacts,
    bool? nonContacts,
    bool? bots,
    bool? unreadOnly,
    bool? excludeMuted,
    bool? excludeArchived,
    bool? excludeBots,
  }) {
    return ChatFolderFilters(
      groups: groups ?? this.groups,
      channels: channels ?? this.channels,
      direct: direct ?? this.direct,
      contacts: contacts ?? this.contacts,
      nonContacts: nonContacts ?? this.nonContacts,
      bots: bots ?? this.bots,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      excludeMuted: excludeMuted ?? this.excludeMuted,
      excludeArchived: excludeArchived ?? this.excludeArchived,
      excludeBots: excludeBots ?? this.excludeBots,
    );
  }

  factory ChatFolderFilters.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatFolderFilters();
    return ChatFolderFilters(
      groups: json['groups'] as bool? ?? false,
      channels: json['channels'] as bool? ?? false,
      direct: json['direct'] as bool? ??
          json['private'] as bool? ??
          false,
      contacts: json['contacts'] as bool? ?? false,
      nonContacts: json['non_contacts'] as bool? ?? false,
      bots: json['bots'] as bool? ?? false,
      unreadOnly: json['unread_only'] as bool? ?? false,
      excludeMuted: json['exclude_muted'] as bool? ?? false,
      excludeArchived: json['exclude_archived'] as bool? ?? false,
      excludeBots: json['exclude_bots'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'channels': channels,
        'direct': direct,
        'contacts': contacts,
        'non_contacts': nonContacts,
        'bots': bots,
        'unread_only': unreadOnly,
        'exclude_muted': excludeMuted,
        'exclude_archived': excludeArchived,
        'exclude_bots': excludeBots,
      };
}

class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.name,
    this.icon,
    this.position = 0,
    this.conversationIds = const [],
    this.channelIds = const [],
    this.filters = const ChatFolderFilters(),
  });

  final int id;
  final String name;
  final String? icon;
  final int position;
  final List<int> conversationIds;
  final List<int> channelIds;
  final ChatFolderFilters filters;

  String get displayLabel {
    final emoji = icon?.trim();
    if (emoji != null && emoji.isNotEmpty) return '$emoji $name';
    return name;
  }

  bool containsConversation(int conversationId) =>
      conversationIds.contains(conversationId);

  bool containsChannel(int channelId) => channelIds.contains(channelId);

  ChatFolder copyWith({
    int? id,
    String? name,
    String? icon,
    int? position,
    List<int>? conversationIds,
    List<int>? channelIds,
    ChatFolderFilters? filters,
  }) {
    return ChatFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      position: position ?? this.position,
      conversationIds: conversationIds ?? this.conversationIds,
      channelIds: channelIds ?? this.channelIds,
      filters: filters ?? this.filters,
    );
  }

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: _parseInt(json['id']),
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      position: _parseInt(json['position']),
      conversationIds: (json['conversation_ids'] as List<dynamic>? ?? [])
          .map(_parseInt)
          .toList(),
      channelIds:
          (json['channel_ids'] as List<dynamic>? ?? []).map(_parseInt).toList(),
      filters: ChatFolderFilters.fromJson(
        json['filters'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'position': position,
        'conversation_ids': conversationIds,
        'channel_ids': channelIds,
        'filters': filters.toJson(),
      };
}

class ChatMessageEditHistoryItem {
  const ChatMessageEditHistoryItem({
    required this.content,
    required this.editedAt,
    this.editorId,
  });

  final String content;
  final DateTime editedAt;
  final int? editorId;

  factory ChatMessageEditHistoryItem.fromJson(Map<String, dynamic> json) {
    return ChatMessageEditHistoryItem(
      content: json['content'] as String? ?? '',
      editedAt: _parseDate(json['edited_at']),
      editorId: json['editor_id'] != null ? _parseInt(json['editor_id']) : null,
    );
  }
}

class ChatMessageEditHistory {
  const ChatMessageEditHistory({
    required this.items,
    this.currentContent = '',
    this.messageType = 'text',
  });

  final List<ChatMessageEditHistoryItem> items;
  final String currentContent;
  final String messageType;

  factory ChatMessageEditHistory.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    final items = <ChatMessageEditHistoryItem>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        items.add(ChatMessageEditHistoryItem.fromJson(item));
      }
    }
    return ChatMessageEditHistory(
      items: items,
      currentContent: json['current_content'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
    );
  }
}

class ChatMessageSearchItem {
  const ChatMessageSearchItem({
    required this.message,
    required this.conversation,
    this.snippet = '',
  });

  final ChatMessage message;
  final ChatConversation conversation;
  final String snippet;

  factory ChatMessageSearchItem.fromJson(Map<String, dynamic> json) {
    final messageRaw = json['message'];
    final conversationRaw = json['conversation'];
    if (messageRaw is! Map<String, dynamic> ||
        conversationRaw is! Map<String, dynamic>) {
      throw FormatException('ChatMessageSearchItem: invalid payload');
    }
    return ChatMessageSearchItem(
      message: ChatMessage.fromJson(messageRaw),
      conversation: ChatConversation.fromJson(conversationRaw),
      snippet: json['snippet'] as String? ?? '',
    );
  }
}

class ScheduledChatMessage {
  const ScheduledChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.content,
    this.mediaUrl,
    this.replyToMessageId,
    required this.sendAt,
    this.sendWhenOnline = false,
    this.silent = false,
    this.disableWebpagePreview = false,
    this.mediaGroupId,
    this.effectId,
    this.topicId,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? replyToMessageId;
  final DateTime sendAt;
  final bool sendWhenOnline;
  final bool silent;
  final bool disableWebpagePreview;
  final String? mediaGroupId;
  final String? effectId;
  final int? topicId;
  final String status;
  final DateTime createdAt;

  factory ScheduledChatMessage.fromJson(Map<String, dynamic> json) {
    final replyRaw = json['reply_to_message_id'];
    final groupRaw = json['media_group_id'] as String?;
    final effectRaw = (json['effect_id'] as String?)?.trim();
    return ScheduledChatMessage(
      id: _parseInt(json['id']),
      conversationId: _parseInt(json['conversation_id']),
      senderId: _parseInt(json['sender_id']),
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      replyToMessageId: replyRaw == null ? null : _parseInt(replyRaw),
      sendAt: _parseDate(json['send_at']),
      sendWhenOnline: json['send_when_online'] as bool? ?? false,
      silent: json['silent'] as bool? ?? false,
      disableWebpagePreview:
          json['disable_webpage_preview'] as bool? ?? false,
      mediaGroupId:
          (groupRaw == null || groupRaw.trim().isEmpty) ? null : groupRaw.trim(),
      effectId: (effectRaw == null || effectRaw.isEmpty) ? null : effectRaw,
      topicId: json['topic_id'] != null ? _parseInt(json['topic_id']) : null,
      status: json['status'] as String? ?? 'pending',
      createdAt: _parseDate(json['created_at']),
    );
  }

  ScheduledChatMessage copyWith({
    String? content,
    DateTime? sendAt,
  }) {
    return ScheduledChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: type,
      content: content ?? this.content,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      sendAt: sendAt ?? this.sendAt,
      sendWhenOnline: sendWhenOnline,
      silent: silent,
      disableWebpagePreview: disableWebpagePreview,
      mediaGroupId: mediaGroupId,
      effectId: effectId,
      topicId: topicId,
      status: status,
      createdAt: createdAt,
    );
  }
}

class ChatForumTopic {
  const ChatForumTopic({
    required this.id,
    required this.conversationId,
    required this.title,
    this.iconEmoji,
    this.isGeneral = false,
    this.closed = false,
    required this.createdAt,
  });

  final int id;
  final int conversationId;
  final String title;
  final String? iconEmoji;
  final bool isGeneral;
  final bool closed;
  final DateTime createdAt;

  String get displayLabel {
    final emoji = (iconEmoji ?? '').trim();
    final name = title.trim().isEmpty ? 'Тема' : title.trim();
    return emoji.isEmpty ? name : '$emoji $name';
  }

  factory ChatForumTopic.fromJson(Map<String, dynamic> json) {
    return ChatForumTopic(
      id: _parseInt(json['id']),
      conversationId: _parseInt(json['conversation_id']),
      title: json['title'] as String? ?? '',
      iconEmoji: (json['icon_emoji'] as String?)?.trim().isEmpty == true
          ? null
          : (json['icon_emoji'] as String?)?.trim(),
      isGeneral: json['is_general'] as bool? ?? false,
      closed: json['closed'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']),
    );
  }

  ChatForumTopic copyWith({
    String? title,
    String? iconEmoji,
    bool clearIconEmoji = false,
    bool? closed,
  }) {
    return ChatForumTopic(
      id: id,
      conversationId: conversationId,
      title: title ?? this.title,
      iconEmoji: clearIconEmoji ? null : (iconEmoji ?? this.iconEmoji),
      isGeneral: isGeneral,
      closed: closed ?? this.closed,
      createdAt: createdAt,
    );
  }
}
