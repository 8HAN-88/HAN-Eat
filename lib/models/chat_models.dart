import 'chat_poll.dart';

export 'chat_poll.dart' show ChatPollMessage, parseChatPollFromContent, chatPollPreviewText, patchChatPollClosedInContent;

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
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final DateTime? lastSeenAt;

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
      isRead: json['is_read'] as bool? ?? false,
      reactions: reactions,
      inlineKeyboard: keyboard,
    );
  }

  ChatMessage copyWith({
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
    this.membersPreview = const [],
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
    this.pinned = false,
    this.archived = false,
    this.muted = false,
    this.createdByUserId,
  });

  final int id;
  final String type;
  final ChatUserBrief? peer;
  final String? title;
  final int memberCount;
  final List<ChatUserBrief> membersPreview;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final bool pinned;
  final bool archived;
  final bool muted;
  final int? createdByUserId;

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
    );
  }

  ChatConversation copyWith({
    String? title,
    int? memberCount,
    List<ChatUserBrief>? membersPreview,
    bool? muted,
    bool? pinned,
  }) {
    return ChatConversation(
      id: id,
      type: type,
      peer: peer,
      title: title ?? this.title,
      memberCount: memberCount ?? this.memberCount,
      membersPreview: membersPreview ?? this.membersPreview,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      updatedAt: updatedAt,
      pinned: pinned ?? this.pinned,
      archived: archived,
      muted: muted ?? this.muted,
      createdByUserId: createdByUserId,
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
      channelIds: (json['channel_ids'] as List<dynamic>? ?? [])
          .map(_parseInt)
          .toList(),
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
