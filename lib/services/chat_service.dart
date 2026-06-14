import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/network/haneat_http_client.dart';
import '../models/chat_models.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'chat_cache_service.dart';
import 'server_config.dart';

class ChatService {
  static String get _base => ServerConfig.apiBaseUrl;
  static const _requestTimeout = Duration(seconds: 12);

  static bool _shouldRetry(int statusCode) =>
      statusCode == 401 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  static Future<Map<String, String>?> _headersOrNull() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final token = await AuthService.getAccessTokenForApi();
      if (token != null && token.isNotEmpty) {
        return {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }

    if (!await AuthService.isAuthenticated()) return null;

    final stale = await AuthService.getAccessToken();
    if (stale != null && stale.isNotEmpty) {
      return {
        'Authorization': 'Bearer $stale',
        'Content-Type': 'application/json',
      };
    }
    return null;
  }

  static Never _throwForResponse(http.Response response, String fallback) {
    throw apiExceptionFromHttpResponse(
      response.statusCode,
      response.body,
      fallback: fallback,
    );
  }

  static void _ensureOk(http.Response response, String fallback) {
    if (response.statusCode == 200 || response.statusCode == 201) return;
    _throwForResponse(response, fallback);
  }

  static Future<String?> _refreshTokenOrNull() async {
    try {
      return await AuthService.refreshToken();
    } catch (_) {
      return null;
    }
  }

  static Future<http.Response> _request(
    Future<http.Response> Function(Map<String, String> headers) request, {
    int retries = 3,
  }) async {
    var headers = await _headersOrNull();
    if (headers == null) {
      if (!await AuthService.isAuthenticated()) {
        return http.Response('{"detail":"offline"}', 503);
      }
      return http.Response('{"detail":"network_error"}', 503);
    }

    Future<http.Response> run(Map<String, String> h) async {
      try {
        return await request(h).timeout(
          _requestTimeout,
          onTimeout: () => http.Response('{"detail":"timeout"}', 504),
        );
      } catch (_) {
        return http.Response('{"detail":"network_error"}', 503);
      }
    }

    var response = await run(headers);
    if (response.statusCode == 401) {
      final token = await _refreshTokenOrNull();
      if (token != null) {
        headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        response = await run(headers);
      }
    }
    if (retries > 0 && _shouldRetry(response.statusCode)) {
      await Future<void>.delayed(
        Duration(milliseconds: 350 * (4 - retries)),
      );
      return _request(request, retries: retries - 1);
    }
    return response;
  }

  static Future<http.Response> _get(Uri uri) =>
      _request((headers) => HanEatHttpClient.shared.get(uri, headers: headers));

  static Future<http.Response> _post(Uri uri, {Object? body}) => _request(
        (headers) => HanEatHttpClient.shared.post(uri, headers: headers, body: body),
      );

  static Future<http.Response> _delete(Uri uri) => _request(
        (headers) => HanEatHttpClient.shared.delete(uri, headers: headers),
      );

  static Future<http.Response> _patch(Uri uri, {Object? body}) => _request(
        (headers) => HanEatHttpClient.shared.patch(uri, headers: headers, body: body),
      );

  static Future<List<ChatConversation>> listConversations({
    bool archived = false,
  }) async {
    final uri = Uri.parse('$_base/chats').replace(
      queryParameters: archived ? {'archived': 'true'} : null,
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить чаты');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatConversation>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(ChatConversation.fromJson(raw));
      } catch (_) {
        // Пропускаем битые записи — не роняем весь список.
      }
    }
    unawaited(ChatCacheService.saveConversations(
      out.where((c) => !c.isSaved).toList(growable: false),
    ));
    return out;
  }

  /// Личное «Избранное» — создаёт чат на сервере при первом вызове.
  static Future<ChatConversation> ensureSavedChat() async {
    final uri = Uri.parse('$_base/chats/saved');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось открыть избранное');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> pingPresence() async {
    final uri = Uri.parse('$_base/users/me/presence');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось обновить статус онлайн');
  }

  static Future<int> unreadCount() async {
    final uri = Uri.parse('$_base/chats/unread-count');
    final response = await _get(uri);
    if (response.statusCode != 200) return 0;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['count'] as int? ?? 0;
  }

  static Future<ChatConversation> getConversation(int conversationId) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить чат');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> createGroupChat({
    required String title,
    required List<int> memberIds,
  }) async {
    final uri = Uri.parse('$_base/chats/group');
    final response = await _post(
      uri,
      body: jsonEncode({
        'title': title,
        'member_ids': memberIds,
      }),
    );
    _ensureOk(response, 'Не удалось создать группу');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatUserBrief>> listMembers(int conversationId) async {
    final uri = Uri.parse('$_base/chats/$conversationId/members');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить участников');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatUserBrief>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatUserBrief.fromJson(raw));
      }
    }
    return out;
  }

  static Future<void> setArchived({
    required int conversationId,
    required bool archived,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/archive');
    final response = await _post(
      uri,
      body: jsonEncode({'archived': archived}),
    );
    _ensureOk(response, 'Не удалось архивировать чат');
  }

  static Future<ChatConversation> openDirectChat(int userId) async {
    final uri = Uri.parse('$_base/chats/direct');
    final response = await _post(
      uri,
      body: jsonEncode({'user_id': userId}),
    );
    _ensureOk(response, 'Не удалось открыть чат');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<({List<ChatMessage> items, bool hasMore, int? nextCursor, ChatMessage? pinnedMessage})>
      listMessages({
    required int conversationId,
    int? cursor,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages').replace(
      queryParameters: {
        if (cursor != null) 'cursor': '$cursor',
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить сообщения');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    ChatMessage? pinnedMessage;
    final pinnedRaw = data['pinned_message'];
    if (pinnedRaw is Map<String, dynamic>) {
      try {
        pinnedMessage = ChatMessage.fromJson(pinnedRaw);
      } catch (_) {}
    }
    return (
      items: items,
      hasMore: data['has_more'] as bool? ?? false,
      nextCursor: data['next_cursor'] as int?,
      pinnedMessage: pinnedMessage,
    );
  }

  /// Только новые сообщения после [afterId] — лёгкий poll вместо полной страницы.
  static Future<List<ChatMessage>> listMessagesAfter({
    required int conversationId,
    required int afterId,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages').replace(
      queryParameters: {
        'after_id': '$afterId',
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось обновить сообщения');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> checkServerReachable() async {
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/health');
      final response = await HanEatHttpClient.shared
          .get(uri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteMessage({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages/$messageId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить сообщение');
  }

  static Future<ChatMessage> editMessage({
    required int conversationId,
    required int messageId,
    required String content,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages/$messageId');
    final response = await _patch(
      uri,
      body: jsonEncode({'content': content}),
    );
    _ensureOk(response, 'Не удалось изменить сообщение');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatReactionSummary>> setReaction({
    required int conversationId,
    required int messageId,
    required String emoji,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/reactions',
    );
    final response = await _post(uri, body: jsonEncode({'emoji': emoji}));
    _ensureOk(response, 'Не удалось поставить реакцию');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseReactions(data['reactions']);
  }

  static Future<List<ChatReactionSummary>> removeReaction({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/reactions',
    );
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось убрать реакцию');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseReactions(data['reactions']);
  }

  static Future<void> pinMessage({
    required int conversationId,
    required int messageId,
    bool pinned = true,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/pin',
    );
    final response = await _post(uri, body: jsonEncode({'pinned': pinned}));
    _ensureOk(response, pinned ? 'Не удалось закрепить' : 'Не удалось открепить');
  }

  static List<ChatReactionSummary> parseReactions(dynamic raw) =>
      _parseReactions(raw);

  static List<ChatReactionSummary> _parseReactions(dynamic raw) {
    if (raw is! List<dynamic>) return const [];
    final out = <ChatReactionSummary>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          out.add(ChatReactionSummary.fromJson(item));
        } catch (_) {}
      }
    }
    return out;
  }

  static Future<ChatMessage> sendText({
    required int conversationId,
    required String content,
    int? replyToMessageId,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'text',
      content: content,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<ChatMessage> sendVoice({
    required int conversationId,
    required String mediaUrl,
    required int durationSec,
    int? replyToMessageId,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'voice',
      content: '$durationSec',
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<ChatMessage> sendImage({
    required int conversationId,
    required String mediaUrl,
    String caption = '',
    int? replyToMessageId,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'image',
      content: caption,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<ChatMessage> sendFile({
    required int conversationId,
    required String mediaUrl,
    required String fileName,
    int? replyToMessageId,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'file',
      content: fileName,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<ChatMessage> sendVideo({
    required int conversationId,
    required String mediaUrl,
    String caption = '',
    int? replyToMessageId,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'video',
      content: caption,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<ChatMessage> _send({
    required int conversationId,
    required String type,
    required String content,
    String? mediaUrl,
    int? replyToMessageId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages');
    final response = await _post(
      uri,
      body: jsonEncode({
        'type': type,
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      }),
    );
    _ensureOk(response, 'Не удалось отправить сообщение');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> markRead({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/read');
    await _post(uri, body: jsonEncode({'message_id': messageId}));
  }

  static Future<void> markUnread({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId/unread');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось пометить непрочитанным');
  }

  static Future<void> deleteConversation({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить чат');
  }

  static Future<List<ChatContact>> listContacts() async {
    final uri = Uri.parse('$_base/contacts');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить контакты');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatContact>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(ChatContact.fromJson(raw));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> addContact(int userId) async {
    final uri = Uri.parse('$_base/contacts');
    final response = await _post(uri, body: jsonEncode({'user_id': userId}));
    _ensureOk(response, 'Не удалось добавить контакт');
  }

  static Future<void> removeContact(int userId) async {
    final uri = Uri.parse('$_base/contacts/$userId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить контакт');
  }

  static Future<void> setPinned({
    required int conversationId,
    required bool pinned,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/pin');
    final response = await _post(
      uri,
      body: jsonEncode({'pinned': pinned}),
    );
    _ensureOk(response, 'Не удалось закрепить чат');
  }

  static Future<void> setMuted({
    required int conversationId,
    required bool muted,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/mute');
    final response = await _post(
      uri,
      body: jsonEncode({'muted': muted}),
    );
    _ensureOk(response, 'Не удалось изменить уведомления');
  }

  static Future<ChatConversation> updateGroupTitle({
    required int conversationId,
    required String title,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'title': title}),
    );
    _ensureOk(response, 'Не удалось переименовать группу');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<int> addGroupMembers({
    required int conversationId,
    required List<int> userIds,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/members');
    final response = await _post(
      uri,
      body: jsonEncode({'user_ids': userIds}),
    );
    _ensureOk(response, 'Не удалось добавить участников');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['added'] as int? ?? 0;
  }

  static Future<void> removeGroupMember({
    required int conversationId,
    required int userId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/members/$userId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить участника');
  }

  static Future<void> leaveGroup({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId/leave');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось выйти из группы');
  }

  static Future<void> blockUser(int userId) async {
    final uri = Uri.parse('$_base/users/$userId/block');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось заблокировать');
  }

  static Future<void> unblockUser(int userId) async {
    final uri = Uri.parse('$_base/users/$userId/block');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось разблокировать');
  }

  static Future<void> sendTyping({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId/typing');
    try {
      await _post(uri);
    } catch (_) {}
  }

  static ChatMessage messageFromStreamPayload(Map<String, dynamic> json) {
    final uid = AuthService.instance.currentUser?.id;
    final msg = ChatMessage.fromJson(json);
    if (uid == null) return msg;
    return ChatMessage(
      id: msg.id,
      conversationId: msg.conversationId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      type: msg.type,
      content: msg.content,
      mediaUrl: msg.mediaUrl,
      replyToMessageId: msg.replyToMessageId,
      createdAt: msg.createdAt,
      editedAt: msg.editedAt,
      isMine: msg.senderId == uid,
      isRead: msg.senderId == uid,
      reactions: msg.reactions,
    );
  }

  static Future<List<ChatUserSearchItem>> syncPhoneContacts(
    List<String> phoneHashes,
  ) async {
    final uri = Uri.parse('$_base/contacts/phone-sync');
    final response = await _post(
      uri,
      body: jsonEncode({'phone_hashes': phoneHashes}),
    );
    _ensureOk(response, 'Не удалось синхронизировать контакты');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChatUserSearchItem.fromJson)
        .toList();
  }

  static Future<List<ChatUserSearchItem>> searchUsers(String query) async {
    final uri = Uri.parse('$_base/users/search').replace(
      queryParameters: {'q': query.trim()},
    );
    final response = await _get(uri);
    _ensureOk(response, 'Поиск не удался');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatUserSearchItem>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(ChatUserSearchItem.fromJson(raw));
      } catch (_) {}
    }
    return out;
  }

  static ChatFolder _folderFromResponse(http.Response response, String fallback) {
    _ensureOk(response, fallback);
    return ChatFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatFolder>> listFolders() async {
    final uri = Uri.parse('$_base/chats/folders');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить папки');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChatFolder.fromJson)
        .toList();
  }

  static Future<ChatFolder> createFolder({
    required String name,
    String? icon,
    List<int> conversationIds = const [],
    List<int> channelIds = const [],
    ChatFolderFilters filters = const ChatFolderFilters(),
  }) async {
    final uri = Uri.parse('$_base/chats/folders');
    final response = await _post(
      uri,
      body: jsonEncode({
        'name': name,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
        'conversation_ids': conversationIds,
        'channel_ids': channelIds,
        'filters': filters.toJson(),
      }),
    );
    return _folderFromResponse(response, 'Не удалось создать папку');
  }

  static Future<ChatFolder> updateFolder({
    required int folderId,
    String? name,
    String? icon,
    List<int>? conversationIds,
    List<int>? channelIds,
    ChatFolderFilters? filters,
  }) async {
    final uri = Uri.parse('$_base/chats/folders/$folderId');
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (conversationIds != null) body['conversation_ids'] = conversationIds;
    if (channelIds != null) body['channel_ids'] = channelIds;
    if (filters != null) body['filters'] = filters.toJson();
    final response = await _patch(uri, body: jsonEncode(body));
    return _folderFromResponse(response, 'Не удалось обновить папку');
  }

  static Future<void> deleteFolder({required int folderId}) async {
    final uri = Uri.parse('$_base/chats/folders/$folderId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить папку');
  }

  static Future<ChatFolder> addFolderItem({
    required int folderId,
    int? conversationId,
    int? channelId,
  }) async {
    final uri = Uri.parse('$_base/chats/folders/$folderId/items');
    final response = await _post(
      uri,
      body: jsonEncode({
        if (conversationId != null) 'conversation_id': conversationId,
        if (channelId != null) 'channel_id': channelId,
      }),
    );
    return _folderFromResponse(response, 'Не удалось добавить в папку');
  }

  static Future<ChatFolder> removeFolderItem({
    required int folderId,
    int? conversationId,
    int? channelId,
  }) async {
    final params = <String, String>{};
    if (conversationId != null) {
      params['conversation_id'] = '$conversationId';
    }
    if (channelId != null) params['channel_id'] = '$channelId';
    final uri = Uri.parse('$_base/chats/folders/$folderId/items')
        .replace(queryParameters: params);
    final response = await _delete(uri);
    return _folderFromResponse(response, 'Не удалось убрать из папки');
  }

  static Future<List<ChatFolder>> reorderFolders(List<int> folderIds) async {
    final uri = Uri.parse('$_base/chats/folders/reorder');
    final response = await _post(
      uri,
      body: jsonEncode({'folder_ids': folderIds}),
    );
    _ensureOk(response, 'Не удалось изменить порядок папок');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChatFolder.fromJson)
        .toList();
  }
}
