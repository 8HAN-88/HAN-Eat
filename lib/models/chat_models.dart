import 'chat_poll.dart';

export 'chat_poll.dart'
    show
        ChatPollMessage,
        parseChatPollFromContent,
        chatPollPreviewText,
        patchChatPollClosedInContent;

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
    this.isGroupAdmin = false,
    this.isGroupCreator = false,
    this.canManageMembers = false,
    this.canManagePostingPermissions = false,
    this.sendRestricted = false,
    this.sendRestrictedUntil,
    this.sendRestrictionReason,
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final DateTime? lastSeenAt;
  final bool isGroupAdmin;
  final bool isGroupCreator;
  final bool canManageMembers;
  final bool canManagePostingPermissions;
  final bool sendRestricted;
  final DateTime? sendRestrictedUntil;
  final String? sendRestrictionReason;

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
      isGroupAdmin: json['is_group_admin'] as bool? ?? false,
      isGroupCreator: json['is_group_creator'] as bool? ?? false,
      canManageMembers: json['can_manage_members'] as bool? ?? false,
      canManagePostingPermissions:
          json['can_manage_posting_permissions'] as bool? ?? false,
      sendRestricted: json['send_restricted'] as bool? ?? false,
      sendRestrictedUntil: json['send_restricted_until'] is String
          ? DateTime.tryParse(json['send_restricted_until'] as String)
          : null,
      sendRestrictionReason: json['send_restriction_reason'] as String?,
    );
  }
}

class ChatReactionSummary {
  const ChatReactionSummary({
    required this.emoji,
    required this.count,
    this.reactedByMe = false,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory ChatReactionSummary.fromJson(Map<String, dynamic> json) {
    return ChatReactionSummary(
      emoji: json['emoji'] as String? ?? '',
      count: _parseInt(json['count']),
      reactedByMe: json['reacted_by_me'] as bool? ?? false,
    );
  }
}

class ChatInlineKeyboardButton {
  const ChatInlineKeyboardButton({
    required this.text,
    this.callbackData,
    this.url,
    this.callbackText,
  });

  final String text;
  final String? callbackData;
  final String? url;
  final String? callbackText;

  factory ChatInlineKeyboardButton.fromJson(Map<String, dynamic> json) {
    return ChatInlineKeyboardButton(
      text: json['text'] as String? ?? '',
      callbackData: json['callback_data'] as String?,
      url: json['url'] as String?,
      callbackText: json['callback_text'] as String?,
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
    required this.createdAt,
    this.editedAt,
    this.isMine = false,
    this.isDelivered = false,
    this.isRead = false,
    this.reactions = const [],
    this.inlineKeyboard = const [],
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String? senderName;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? replyToMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isMine;
  /// Peer device received the message (Telegram gray ✓✓).
  final bool isDelivered;
  final bool isRead;
  final List<ChatReactionSummary> reactions;
  final List<List<ChatInlineKeyboardButton>> inlineKeyboard;

  bool get isEdited => editedAt != null;

  ChatPollMessage? get poll =>
      type == 'poll' ? parseChatPollFromContent(content) : null;

  int? get voiceDurationSec {
    if (type != 'voice') return null;
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
      createdAt: _parseDate(json['created_at']),
      editedAt: editedAt,
      isMine: json['is_mine'] as bool? ?? false,
      isDelivered: json['is_delivered'] as bool? ??
          (json['is_read'] as bool? ?? false),
      isRead: json['is_read'] as bool? ?? false,
      reactions: reactions,
      inlineKeyboard: keyboard,
    );
  }

  ChatMessage copyWith({
    bool? isDelivered,
    bool? isRead,
    String? content,
    DateTime? editedAt,
    List<ChatReactionSummary>? reactions,
    List<List<ChatInlineKeyboardButton>>? inlineKeyboard,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      type: type,
      content: content ?? this.content,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      isMine: isMine,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      reactions: reactions ?? this.reactions,
      inlineKeyboard: inlineKeyboard ?? this.inlineKeyboard,
    );
  }
}

/// Не затирает локально закрытый опрос устаревшими данными чата/кэша.
ChatMessage applyIncomingChatMessagePreservingLocalPoll(
  ChatMessage local,
  ChatMessage incoming,
) {
  if (local.type != 'poll' || incoming.type != 'poll') return incoming;
  final localPoll = local.poll;
  final incomingPoll = incoming.poll;
  if (localPoll == null ||
      incomingPoll == null ||
      !localPoll.isClosed ||
      incomingPoll.isClosed) {
    return incoming;
  }
  return incoming.copyWith(
    content: patchChatPollClosedInContent(incoming.content, isClosed: true),
  );
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.type,
    this.peer,
    this.title,
    this.memberCount = 0,
    this.pendingJoinRequestsCount = 0,
    this.membersPreview = const [],
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
    this.pinned = false,
    this.archived = false,
    this.muted = false,
    this.createdByUserId,
    this.onlyAdminsCanPost = false,
    this.joinByRequestEnabled = false,
    this.slowModeSeconds = 0,
    this.antiFloodMaxMessagesPerMinute = 0,
    this.amIGroupAdmin = false,
    this.amICanManageMembers = false,
    this.amICanManagePostingPermissions = false,
    this.amISendRestricted = false,
    this.amISendRestrictedUntil,
    this.amISendRestrictionReason,
  });

  final int id;
  final String type;
  final ChatUserBrief? peer;
  final String? title;
  final int memberCount;
  final int pendingJoinRequestsCount;
  final List<ChatUserBrief> membersPreview;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final bool pinned;
  final bool archived;
  final bool muted;
  final int? createdByUserId;
  final bool onlyAdminsCanPost;
  final bool joinByRequestEnabled;
  final int slowModeSeconds;
  final int antiFloodMaxMessagesPerMinute;
  final bool amIGroupAdmin;
  final bool amICanManageMembers;
  final bool amICanManagePostingPermissions;
  final bool amISendRestricted;
  final DateTime? amISendRestrictedUntil;
  final String? amISendRestrictionReason;

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
      memberCount: _parseInt(json['member_count']),
      pendingJoinRequestsCount: _parseInt(json['pending_join_requests_count']),
      membersPreview: preview,
      lastMessage: lastMessage,
      unreadCount: _parseInt(json['unread_count']),
      updatedAt: _parseDate(json['updated_at']),
      pinned: json['pinned'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      createdByUserId: json['created_by_user_id'] != null
          ? _parseInt(json['created_by_user_id'])
          : null,
      onlyAdminsCanPost: json['only_admins_can_post'] as bool? ?? false,
      joinByRequestEnabled: json['join_by_request_enabled'] as bool? ?? false,
      slowModeSeconds: _parseInt(json['slow_mode_seconds']),
      antiFloodMaxMessagesPerMinute:
          _parseInt(json['anti_flood_max_messages_per_minute']),
      amIGroupAdmin: json['am_i_group_admin'] as bool? ?? false,
      amICanManageMembers: json['am_i_can_manage_members'] as bool? ?? false,
      amICanManagePostingPermissions:
          json['am_i_can_manage_posting_permissions'] as bool? ?? false,
      amISendRestricted: json['am_i_send_restricted'] as bool? ?? false,
      amISendRestrictedUntil: json['am_i_send_restricted_until'] is String
          ? DateTime.tryParse(json['am_i_send_restricted_until'] as String)
          : null,
      amISendRestrictionReason: json['am_i_send_restriction_reason'] as String?,
    );
  }

  ChatConversation copyWith({
    String? title,
    int? memberCount,
    int? pendingJoinRequestsCount,
    List<ChatUserBrief>? membersPreview,
    int? unreadCount,
    bool? muted,
    bool? pinned,
    bool? onlyAdminsCanPost,
    bool? joinByRequestEnabled,
    int? slowModeSeconds,
    int? antiFloodMaxMessagesPerMinute,
    bool? amIGroupAdmin,
    bool? amICanManageMembers,
    bool? amICanManagePostingPermissions,
    bool? amISendRestricted,
    DateTime? amISendRestrictedUntil,
    String? amISendRestrictionReason,
  }) {
    return ChatConversation(
      id: id,
      type: type,
      peer: peer,
      title: title ?? this.title,
      memberCount: memberCount ?? this.memberCount,
      pendingJoinRequestsCount:
          pendingJoinRequestsCount ?? this.pendingJoinRequestsCount,
      membersPreview: membersPreview ?? this.membersPreview,
      lastMessage: lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt,
      pinned: pinned ?? this.pinned,
      archived: archived,
      muted: muted ?? this.muted,
      createdByUserId: createdByUserId,
      onlyAdminsCanPost: onlyAdminsCanPost ?? this.onlyAdminsCanPost,
      joinByRequestEnabled: joinByRequestEnabled ?? this.joinByRequestEnabled,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      antiFloodMaxMessagesPerMinute:
          antiFloodMaxMessagesPerMinute ?? this.antiFloodMaxMessagesPerMinute,
      amIGroupAdmin: amIGroupAdmin ?? this.amIGroupAdmin,
      amICanManageMembers: amICanManageMembers ?? this.amICanManageMembers,
      amICanManagePostingPermissions:
          amICanManagePostingPermissions ?? this.amICanManagePostingPermissions,
      amISendRestricted: amISendRestricted ?? this.amISendRestricted,
      amISendRestrictedUntil:
          amISendRestrictedUntil ?? this.amISendRestrictedUntil,
      amISendRestrictionReason:
          amISendRestrictionReason ?? this.amISendRestrictionReason,
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
    this.unreadOnly = false,
  });

  final bool groups;
  final bool channels;
  final bool unreadOnly;

  bool get isEmpty => !groups && !channels && !unreadOnly;

  ChatFolderFilters copyWith({
    bool? groups,
    bool? channels,
    bool? unreadOnly,
  }) {
    return ChatFolderFilters(
      groups: groups ?? this.groups,
      channels: channels ?? this.channels,
      unreadOnly: unreadOnly ?? this.unreadOnly,
    );
  }

  factory ChatFolderFilters.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatFolderFilters();
    return ChatFolderFilters(
      groups: json['groups'] as bool? ?? false,
      channels: json['channels'] as bool? ?? false,
      unreadOnly: json['unread_only'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'channels': channels,
        'unread_only': unreadOnly,
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
  final String status;
  final DateTime createdAt;

  factory ScheduledChatMessage.fromJson(Map<String, dynamic> json) {
    final replyRaw = json['reply_to_message_id'];
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
      status: json['status'] as String? ?? 'pending',
      createdAt: _parseDate(json['created_at']),
    );
  }
}
