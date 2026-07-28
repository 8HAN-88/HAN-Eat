import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/network/api_endpoint_resolver.dart';
import '../core/network/api_rate_limit_backoff.dart';
import '../core/network/haneat_http_client.dart';
import '../models/chat_models.dart';
import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'chat_cache_service.dart';
import 'server_config.dart';

class ChatService {
  static String get _base => ServerConfig.apiBaseUrl;
  static const _requestTimeout = Duration(seconds: 12);
  static const _sendTimeout = Duration(seconds: 35);

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
    Future<http.Response> Function(
      http.Client client,
      Map<String, String> headers,
    ) request, {
    int retries = 3,
    Duration? timeout,
    bool bypassRateLimitGate = false,
  }) async {
    // Chat sends must never wait on a global backoff from unrelated 429s
    // (feed/health) — that made messages appear "seconds later" like a queue.
    if (!bypassRateLimitGate && ApiRateLimitBackoff.isActive) {
      final sec = ApiRateLimitBackoff.remaining?.inSeconds ?? 60;
      return http.Response(
        '{"detail":"Too many requests. Please try again later.","code":"RATE_LIMIT_EXCEEDED"}',
        429,
        headers: {'retry-after': '$sec'},
      );
    }

    final effectiveTimeout = timeout ?? _requestTimeout;
    var headers = await _headersOrNull();
    if (headers == null) {
      if (!await AuthService.isAuthenticated()) {
        return http.Response('{"detail":"offline"}', 503);
      }
      return http.Response('{"detail":"network_error"}', 503);
    }

    Future<http.Response> run(Map<String, String> h) async {
      try {
        return await HanEatHttpClient.withShared(
          (client) => request(client, h).timeout(
            effectiveTimeout,
            onTimeout: () => http.Response('{"detail":"timeout"}', 504),
          ),
        );
      } catch (_) {
        HanEatHttpClient.recreateShared();
        await ApiEndpointResolver.revalidateIfNeeded();
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
    if (response.statusCode == 429) {
      final retryAfter =
          int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      // Don't freeze the whole app after a chat send 429.
      if (!bypassRateLimitGate) {
        ApiRateLimitBackoff.register(retryAfterSeconds: retryAfter);
      }
      return response;
    }
    if (retries > 0 && _shouldRetry(response.statusCode)) {
      if (response.statusCode == 503 || response.statusCode == 504) {
        HanEatHttpClient.recreateShared();
        await ApiEndpointResolver.revalidateIfNeeded();
      }
      await Future<void>.delayed(
        Duration(milliseconds: bypassRateLimitGate ? 120 : (350 * (4 - retries))),
      );
      return _request(
        request,
        retries: retries - 1,
        timeout: timeout,
        bypassRateLimitGate: bypassRateLimitGate,
      );
    }
    return response;
  }

  static Future<http.Response> _get(Uri uri) => _request(
        (client, headers) => client.get(uri, headers: headers),
      );

  static Future<http.Response> _post(
    Uri uri, {
    Object? body,
    int retries = 3,
    Duration? timeout,
    bool bypassRateLimitGate = false,
  }) =>
      _request(
        (client, headers) => client.post(uri, headers: headers, body: body),
        retries: retries,
        timeout: timeout,
        bypassRateLimitGate: bypassRateLimitGate,
      );

  static Future<http.Response> _delete(Uri uri) => _request(
        (client, headers) => client.delete(uri, headers: headers),
      );

  static Future<http.Response> _patch(Uri uri, {Object? body}) => _request(
        (client, headers) => client.patch(uri, headers: headers, body: body),
      );

  static Future<http.Response> _put(Uri uri, {Object? body}) => _request(
        (client, headers) => client.put(uri, headers: headers, body: body),
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

  static Future<
      ({
        List<ChatMessage> items,
        bool hasMore,
        int? nextCursor,
        ChatMessage? pinnedMessage,
        List<ChatMessage> pinnedMessages,
      })> listMessages({
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
    final pinnedMessages = <ChatMessage>[];
    final pinnedListRaw = data['pinned_messages'];
    if (pinnedListRaw is List) {
      for (final raw in pinnedListRaw) {
        if (raw is Map<String, dynamic>) {
          try {
            pinnedMessages.add(ChatMessage.fromJson(raw));
          } catch (_) {}
        }
      }
    }
    ChatMessage? pinnedMessage;
    if (pinnedMessages.isNotEmpty) {
      pinnedMessage = pinnedMessages.first;
    } else {
      final pinnedRaw = data['pinned_message'];
      if (pinnedRaw is Map<String, dynamic>) {
        try {
          pinnedMessage = ChatMessage.fromJson(pinnedRaw);
          if (pinnedMessage != null) pinnedMessages.add(pinnedMessage);
        } catch (_) {}
      }
    }
    return (
      items: items,
      hasMore: data['has_more'] as bool? ?? false,
      nextCursor: data['next_cursor'] as int?,
      pinnedMessage: pinnedMessage,
      pinnedMessages: pinnedMessages,
    );
  }

  /// Returns conversationId → draft from cloud.
  static Future<Map<int, ChatDraft>> listCloudDraftsByConversation() async {
    final uri = Uri.parse('$_base/chats/drafts');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить черновики');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    final out = <int, ChatDraft>{};
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final cid = raw['conversation_id'];
      final id = cid is int ? cid : int.tryParse('$cid');
      if (id == null) continue;
      try {
        final draft = ChatDraft.fromJson(raw);
        if (!draft.isEmpty) out[id] = draft;
      } catch (_) {}
    }
    return out;
  }

  static Future<ChatDraft?> upsertCloudDraft({
    required int conversationId,
    required String text,
    int? replyToMessageId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (replyToMessageId == null || replyToMessageId <= 0)) {
      await deleteCloudDraft(conversationId: conversationId);
      return null;
    }
    final uri = Uri.parse('$_base/chats/$conversationId/draft');
    final response = await _put(
      uri,
      body: jsonEncode({
        'text': trimmed,
        if (replyToMessageId != null && replyToMessageId > 0)
          'reply_to_message_id': replyToMessageId,
      }),
    );
    if (response.statusCode == 400) return null;
    _ensureOk(response, 'Не удалось сохранить черновик');
    return ChatDraft.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> deleteCloudDraft({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId/draft');
    final response = await _delete(uri);
    if (response.statusCode == 404) return;
    _ensureOk(response, 'Не удалось удалить черновик');
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
      final response = await HanEatHttpClient.withShared(
        (client) => client.get(uri).timeout(const Duration(seconds: 5)),
      );
      return response.statusCode == 200;
    } catch (_) {
      HanEatHttpClient.recreateShared();
      return false;
    }
  }

  static Future<void> deleteMessage({
    required int conversationId,
    required int messageId,
    /// `me` — только у себя; `all` — у всех (только свои сообщения).
    String scope = 'all',
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId',
    ).replace(queryParameters: {'scope': scope});
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось удалить сообщение');
  }

  static Future<ChatMessageReadersResult> listMessageReaders({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/readers',
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить, кто прочитал');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    final readers = <ChatUserBrief>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final userRaw = raw['user'];
      if (userRaw is Map<String, dynamic>) {
        readers.add(ChatUserBrief.fromJson(userRaw));
      }
    }
    return ChatMessageReadersResult(
      readers: readers,
      readerCount: (data['reader_count'] as num?)?.toInt() ?? readers.length,
      otherMemberCount: (data['other_member_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<ChatMessageReactionsResult> listMessageReactions({
    required int conversationId,
    required int messageId,
    String? emoji,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/reactions',
    ).replace(
      queryParameters: {
        if (emoji != null && emoji.trim().isNotEmpty) 'emoji': emoji.trim(),
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить реакции');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final itemsRaw = data['items'] as List<dynamic>? ?? const [];
    final items = <ChatMessageReactionUser>[];
    for (final raw in itemsRaw) {
      if (raw is! Map<String, dynamic>) continue;
      final userRaw = raw['user'];
      if (userRaw is! Map<String, dynamic>) continue;
      try {
        items.add(
          ChatMessageReactionUser(
            emoji: raw['emoji'] as String? ?? '',
            user: ChatUserBrief.fromJson(userRaw),
          ),
        );
      } catch (_) {}
    }
    return ChatMessageReactionsResult(
      items: items,
      reactionCount:
          (data['reaction_count'] as num?)?.toInt() ?? items.length,
    );
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

  static Future<ChatMessageEditHistory> listMessageEdits({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/edits',
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить историю правок');
    return ChatMessageEditHistory.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<String> translateText({
    required String text,
    String targetLang = 'ru',
  }) async {
    final uri = Uri.parse('$_base/chats/translate');
    final response = await _post(
      uri,
      body: jsonEncode({
        'text': text,
        'target_lang': targetLang,
      }),
    );
    _ensureOk(response, 'Не удалось перевести сообщение');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['translated'] as String?)?.trim().isNotEmpty == true
        ? (data['translated'] as String)
        : text;
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
    _ensureOk(
        response, pinned ? 'Не удалось закрепить' : 'Не удалось открепить');
  }

  static Future<void> clearPinnedMessages({
    required int conversationId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/pins/clear');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось открепить все сообщения');
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
    String? clientMessageId,
    bool silent = false,
    bool disableWebpagePreview = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'text',
      content: content,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
      disableWebpagePreview: disableWebpagePreview,
    );
  }

  static Future<ChatMessage> sendLocation({
    required int conversationId,
    required String content,
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'location',
      content: content,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> forwardMessage({
    required int targetConversationId,
    required int sourceConversationId,
    required int messageId,
    bool asCopy = false,
  }) async {
    final uri =
        Uri.parse('$_base/chats/$targetConversationId/messages/forward');
    final response = await _post(
      uri,
      retries: 1,
      timeout: _sendTimeout,
      bypassRateLimitGate: true,
      body: jsonEncode({
        'source_conversation_id': sourceConversationId,
        'message_id': messageId,
        'as_copy': asCopy,
      }),
    );
    _ensureOk(response, 'Не удалось переслать сообщение');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatBotCommand>> listConversationBotCommands({
    required int conversationId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/bot-commands');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить команды бота');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    final out = <ChatBotCommand>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        final cmd = ChatBotCommand.fromJson(raw);
        if (cmd.command.isNotEmpty) out.add(cmd);
      } catch (_) {}
    }
    return out;
  }

  static Future<ScheduledChatMessage> scheduleText({
    required int conversationId,
    required String content,
    required DateTime sendAt,
    bool sendWhenOnline = false,
    int? replyToMessageId,
    String? clientMessageId,
  }) async {
    return scheduleMessage(
      conversationId: conversationId,
      type: 'text',
      content: content,
      sendAt: sendAt,
      sendWhenOnline: sendWhenOnline,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
    );
  }

  static Future<ScheduledChatMessage> scheduleMessage({
    required int conversationId,
    required String type,
    required String content,
    required DateTime sendAt,
    bool sendWhenOnline = false,
    String? mediaUrl,
    int? replyToMessageId,
    String? clientMessageId,
    String? pollQuestion,
    String? pollDescription,
    List<String>? pollOptions,
    Map<String, dynamic>? pollSettings,
  }) {
    return _scheduleMessage(
      conversationId: conversationId,
      type: type,
      content: content,
      sendAt: sendAt,
      sendWhenOnline: sendWhenOnline,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      pollQuestion: pollQuestion,
      pollDescription: pollDescription,
      pollOptions: pollOptions,
      pollSettings: pollSettings,
    );
  }

  static Future<ChatMessage> sendVoice({
    required int conversationId,
    required String mediaUrl,
    required int durationSec,
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'voice',
      content: '$durationSec',
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendImage({
    required int conversationId,
    required String mediaUrl,
    String caption = '',
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'image',
      content: caption,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendFile({
    required int conversationId,
    required String mediaUrl,
    required String fileName,
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'file',
      content: fileName,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendVideo({
    required int conversationId,
    required String mediaUrl,
    String caption = '',
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'video',
      content: caption,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendVideoNote({
    required int conversationId,
    required String mediaUrl,
    int durationSec = 1,
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'video_note',
      content: '${durationSec < 1 ? 1 : durationSec}',
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendSticker({
    required int conversationId,
    required String mediaUrl,
    String emoji = '',
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
  }) async {
    return _send(
      conversationId: conversationId,
      type: 'sticker',
      content: emoji,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      clientMessageId: clientMessageId,
      silent: silent,
    );
  }

  static Future<ChatMessage> sendPoll({
    required int conversationId,
    required String question,
    required List<String> options,
    String description = '',
    Map<String, dynamic>? settings,
    int? replyToMessageId,
    bool silent = false,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages');
    final response = await _post(
      uri,
      retries: 0,
      timeout: _sendTimeout,
      body: jsonEncode({
        'type': 'poll',
        'poll_question': question,
        'poll_description': description,
        'poll_options': options,
        if (settings != null) 'poll_settings': settings,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (silent) 'silent': true,
      }),
    );
    _ensureOk(response, 'Не удалось отправить опрос');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatMessage> votePoll({
    required int conversationId,
    required int messageId,
    required int optionIndex,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/poll/vote',
    );
    final response = await _post(
      uri,
      body: jsonEncode({'option_index': optionIndex}),
    );
    _ensureOk(response, 'Не удалось проголосовать');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatMessage> closePoll({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/poll/close',
    );
    final response = await _post(uri, body: jsonEncode({}));
    _ensureOk(response, 'Не удалось закрыть опрос');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatPollVotersResult> listPollVoters({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/poll/voters',
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить голоса');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatPollVotersResult.fromJson(data);
  }

  static Future<ChatMessage> addPollOption({
    required int conversationId,
    required int messageId,
    required String text,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/poll/options',
    );
    final response = await _post(
      uri,
      body: jsonEncode({'text': text.trim()}),
    );
    _ensureOk(response, 'Не удалось добавить вариант');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatMessage> sendInlineCallback({
    required int conversationId,
    required int messageId,
    required String data,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/$messageId/callback',
    );
    final response = await _post(uri, body: jsonEncode({'data': data}));
    _ensureOk(response, 'Не удалось выполнить действие кнопки');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatMessage> _send({
    required int conversationId,
    required String type,
    required String content,
    String? mediaUrl,
    int? replyToMessageId,
    String? clientMessageId,
    bool silent = false,
    bool disableWebpagePreview = false,
  }) async {
    // Fire immediately — never await a global rate-limit pause.
    final uri = Uri.parse('$_base/chats/$conversationId/messages');
    final response = await _post(
      uri,
      retries: 1,
      timeout: _sendTimeout,
      bypassRateLimitGate: true,
      body: jsonEncode({
        'type': type,
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
        if (silent) 'silent': true,
        if (disableWebpagePreview) 'disable_webpage_preview': true,
      }),
    );
    _ensureOk(response, 'Не удалось отправить сообщение');
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ScheduledChatMessage> _scheduleMessage({
    required int conversationId,
    required String type,
    required String content,
    required DateTime sendAt,
    bool sendWhenOnline = false,
    String? mediaUrl,
    int? replyToMessageId,
    String? clientMessageId,
    String? pollQuestion,
    String? pollDescription,
    List<String>? pollOptions,
    Map<String, dynamic>? pollSettings,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/messages/scheduled');
    final response = await _post(
      uri,
      retries: 2,
      timeout: _sendTimeout,
      body: jsonEncode({
        'type': type,
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
        if (pollQuestion != null) 'poll_question': pollQuestion,
        if (pollDescription != null) 'poll_description': pollDescription,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (pollSettings != null) 'poll_settings': pollSettings,
        'send_at': sendAt.toUtc().toIso8601String(),
        'send_when_online': sendWhenOnline,
      }),
    );
    _ensureOk(response, 'Не удалось запланировать сообщение');
    return ScheduledChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ScheduledChatMessage>> listScheduledMessages({
    required int conversationId,
    int limit = 100,
  }) async {
    final uri =
        Uri.parse('$_base/chats/$conversationId/messages/scheduled').replace(
      queryParameters: {'limit': '$limit'},
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить отложенные сообщения');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ScheduledChatMessage>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(ScheduledChatMessage.fromJson(raw));
      } catch (_) {}
    }
    return out;
  }

  static Future<ScheduledChatMessage> cancelScheduledMessage({
    required int conversationId,
    required int scheduledMessageId,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/scheduled/$scheduledMessageId',
    );
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось отменить отложенное сообщение');
    return ScheduledChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ScheduledChatMessage> rescheduleMessage({
    required int conversationId,
    required int scheduledMessageId,
    DateTime? sendAt,
    String? content,
  }) async {
    if (sendAt == null && content == null) {
      throw ArgumentError('sendAt or content required');
    }
    final uri = Uri.parse(
      '$_base/chats/$conversationId/messages/scheduled/$scheduledMessageId',
    );
    final response = await _patch(
      uri,
      body: jsonEncode({
        if (sendAt != null) 'send_at': sendAt.toUtc().toIso8601String(),
        if (content != null) 'content': content,
      }),
    );
    _ensureOk(
      response,
      content != null
          ? 'Не удалось изменить отложенное сообщение'
          : 'Не удалось перенести отложенное сообщение',
    );
    return ScheduledChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> markDelivered({
    required int conversationId,
    required int messageId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/delivered');
    try {
      await _post(uri, body: jsonEncode({'message_id': messageId}));
    } catch (_) {}
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

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static Future<int> clearHistory({required int conversationId}) async {
    final uri = Uri.parse('$_base/chats/$conversationId/clear-history');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось очистить историю');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _asInt(data['cleared_before_id']);
  }

  static Future<List<ChatConversation>> listCommonGroups({
    required int peerUserId,
  }) async {
    final uri = Uri.parse('$_base/users/$peerUserId/common-groups');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить общие группы');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    final out = <ChatConversation>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(
          ChatConversation(
            id: _asInt(raw['id']),
            type: raw['type'] as String? ?? 'group',
            title: raw['title'] as String?,
            memberCount: _asInt(raw['member_count']),
            updatedAt: DateTime.now(),
          ),
        );
      } catch (_) {}
    }
    return out;
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
    DateTime? mutedUntil,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/mute');
    final response = await _post(
      uri,
      body: jsonEncode({
        'muted': muted,
        if (muted && mutedUntil != null)
          'muted_until': mutedUntil.toUtc().toIso8601String(),
      }),
    );
    _ensureOk(response, 'Не удалось изменить уведомления');
  }

  static Future<void> setWallpaperStyle({
    required int conversationId,
    required String? style,
    bool applyToAll = false,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/wallpaper');
    final response = await _post(
      uri,
      body: jsonEncode({
        'style': style,
        'apply_to_all': applyToAll,
      }),
    );
    _ensureOk(response, 'Не удалось сохранить обои');
  }

  static Future<void> setBubbleAccent({
    required int conversationId,
    required String? accent,
    bool applyToAll = false,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/bubble-accent');
    final response = await _post(
      uri,
      body: jsonEncode({
        'accent': accent,
        'apply_to_all': applyToAll,
      }),
    );
    _ensureOk(response, 'Не удалось сохранить цвет пузырей');
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

  static Future<ChatConversation> updateGroupAvatar({
    required int conversationId,
    required String avatarUrl,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'avatar_url': avatarUrl}),
    );
    _ensureOk(response, 'Не удалось обновить фото группы');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setGroupOnlyAdminsCanPost({
    required int conversationId,
    required bool onlyAdminsCanPost,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'only_admins_can_post': onlyAdminsCanPost}),
    );
    _ensureOk(response, 'Не удалось обновить права отправки');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setGroupJoinByRequestEnabled({
    required int conversationId,
    required bool enabled,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'join_by_request_enabled': enabled}),
    );
    _ensureOk(response, 'Не удалось обновить режим вступления');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setGroupProtectContent({
    required int conversationId,
    required bool enabled,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'protect_content': enabled}),
    );
    _ensureOk(response, 'Не удалось обновить защиту контента');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setAutoDeleteSeconds({
    required int conversationId,
    required int seconds,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'auto_delete_seconds': seconds}),
    );
    _ensureOk(response, 'Не удалось обновить автоудаление');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setGroupSlowModeSeconds({
    required int conversationId,
    required int seconds,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({'slow_mode_seconds': seconds}),
    );
    _ensureOk(response, 'Не удалось обновить slow mode');
    return ChatConversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatConversation> setGroupAntiFloodLimit({
    required int conversationId,
    required int maxMessagesPerMinute,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId');
    final response = await _patch(
      uri,
      body: jsonEncode({
        'anti_flood_max_messages_per_minute': maxMessagesPerMinute,
      }),
    );
    _ensureOk(response, 'Не удалось обновить антифлуд лимит');
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

  static Future<void> setGroupMemberAdmin({
    required int conversationId,
    required int userId,
    required bool isAdmin,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/members/$userId/admin',
    );
    final response = await _patch(
      uri,
      body: jsonEncode({'is_admin': isAdmin}),
    );
    _ensureOk(response, 'Не удалось обновить роль модератора');
  }

  static Future<void> setGroupMemberPermissions({
    required int conversationId,
    required int userId,
    required bool canManageMembers,
    required bool canManagePostingPermissions,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/members/$userId/permissions',
    );
    final response = await _patch(
      uri,
      body: jsonEncode({
        'can_manage_members': canManageMembers,
        'can_manage_posting_permissions': canManagePostingPermissions,
      }),
    );
    _ensureOk(response, 'Не удалось обновить права модератора');
  }

  static Future<void> setGroupMemberSendRestriction({
    required int conversationId,
    required int userId,
    required bool sendRestricted,
    DateTime? sendRestrictedUntil,
    String? reason,
  }) async {
    final uri = Uri.parse(
      '$_base/chats/$conversationId/members/$userId/send-restriction',
    );
    final response = await _patch(
      uri,
      body: jsonEncode({
        'send_restricted': sendRestricted,
        'send_restricted_until': sendRestrictedUntil?.toUtc().toIso8601String(),
        'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
      }),
    );
    _ensureOk(response, 'Не удалось обновить ограничения участника');
  }

  static Future<void> banGroupMember({
    required int conversationId,
    required int userId,
    String? reason,
    DateTime? bannedUntil,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/bans/$userId');
    final response = await _post(
      uri,
      body: jsonEncode({
        'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
        'banned_until': bannedUntil?.toUtc().toIso8601String(),
      }),
    );
    _ensureOk(response, 'Не удалось заблокировать участника');
  }

  static Future<void> unbanGroupMember({
    required int conversationId,
    required int userId,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/bans/$userId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось снять блокировку');
  }

  static Future<List<ChatGroupBanEntry>> listGroupBans(
    int conversationId, {
    int limit = 200,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/bans').replace(
      queryParameters: {'limit': '$limit'},
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить бан-лист');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatGroupBanEntry>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatGroupBanEntry.fromJson(raw));
      }
    }
    return out;
  }

  static Future<ChatGroupInviteLink> getGroupInviteLink(
    int conversationId,
  ) async {
    final uri = Uri.parse('$_base/chats/$conversationId/invite-link');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить ссылку-приглашение');
    return ChatGroupInviteLink.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatGroupInviteLink> rotateGroupInviteLink(
    int conversationId,
  ) async {
    final uri = Uri.parse('$_base/chats/$conversationId/invite-link/rotate');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось обновить ссылку-приглашение');
    return ChatGroupInviteLink.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<ChatJoinByInviteResult> joinGroupByInviteToken(
    String token,
  ) async {
    final clean = token.trim();
    final uri = Uri.parse('$_base/chats/join/$clean');
    final response = await _post(uri);
    _ensureOk(response, 'Не удалось вступить в группу');
    return ChatJoinByInviteResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatGroupInviteLink>> listGroupInviteLinks(
    int conversationId, {
    bool includeRevoked = true,
    int limit = 200,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/invite-links').replace(
      queryParameters: {
        'include_revoked': includeRevoked ? 'true' : 'false',
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить ссылки-приглашения');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatGroupInviteLink>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatGroupInviteLink.fromJson(raw));
      }
    }
    return out;
  }

  static Future<ChatGroupInviteLink> createGroupInviteLink(
    int conversationId, {
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/invite-links');
    final response = await _post(
      uri,
      body: jsonEncode({
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'max_uses': maxUses,
      }),
    );
    _ensureOk(response, 'Не удалось создать ссылку-приглашение');
    return ChatGroupInviteLink.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> revokeGroupInviteLink({
    required int conversationId,
    required int inviteLinkId,
  }) async {
    final uri =
        Uri.parse('$_base/chats/$conversationId/invite-links/$inviteLinkId');
    final response = await _delete(uri);
    _ensureOk(response, 'Не удалось отозвать ссылку');
  }

  static Future<List<ChatGroupJoinRequest>> listGroupJoinRequests(
    int conversationId, {
    String status = 'pending',
    int limit = 200,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/join-requests').replace(
      queryParameters: {
        'status': status,
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить заявки');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatGroupJoinRequest>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatGroupJoinRequest.fromJson(raw));
      }
    }
    return out;
  }

  static Future<void> reviewGroupJoinRequest({
    required int conversationId,
    required int requestId,
    required bool approve,
  }) async {
    final uri =
        Uri.parse('$_base/chats/$conversationId/join-requests/$requestId');
    final response = await _patch(
      uri,
      body: jsonEncode({'approve': approve}),
    );
    _ensureOk(response, 'Не удалось обработать заявку');
  }

  static Future<List<ChatJoinRequestsInboxItem>> listJoinRequestsInbox({
    int limit = 200,
  }) async {
    final uri = Uri.parse('$_base/chats/join-requests/inbox').replace(
      queryParameters: {'limit': '$limit'},
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить инбокс заявок');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatJoinRequestsInboxItem>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatJoinRequestsInboxItem.fromJson(raw));
      }
    }
    return out;
  }

  static Future<List<ChatGroupModerationLogItem>> listGroupModerationLog(
    int conversationId, {
    String action = 'all',
    int limit = 200,
  }) async {
    final uri =
        Uri.parse('$_base/chats/$conversationId/moderation-log').replace(
      queryParameters: {
        'action': action,
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить историю модерации');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatGroupModerationLogItem>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        out.add(ChatGroupModerationLogItem.fromJson(raw));
      }
    }
    return out;
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

  static Future<List<ChatUserBrief>> listBlockedUsers() async {
    final uri = Uri.parse('$_base/users/me/blocked');
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить чёрный список');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    final out = <ChatUserBrief>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        try {
          out.add(ChatUserBrief.fromJson(raw));
        } catch (_) {}
      }
    }
    return out;
  }

  static Future<void> sendTyping({
    required int conversationId,
    String activity = 'typing',
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/typing');
    final kind = activity == 'recording' ? 'recording' : 'typing';
    try {
      await _post(uri, body: jsonEncode({'activity': kind}));
    } catch (_) {}
  }

  static ChatMessage messageFromStreamPayload(Map<String, dynamic> json) {
    final uid = AuthService.instance.currentUser?.id;
    final msg = ChatMessage.fromJson(json);
    if (uid == null) return msg;
    final mine = msg.senderId == uid;
    return ChatMessage(
      id: msg.id,
      conversationId: msg.conversationId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      type: msg.type,
      content: msg.content,
      mediaUrl: msg.mediaUrl,
      replyToMessageId: msg.replyToMessageId,
      forwardFromUserId: msg.forwardFromUserId,
      forwardFromName: msg.forwardFromName,
      forwardedFromMessageId: msg.forwardedFromMessageId,
      forwardedFromConversationId: msg.forwardedFromConversationId,
      createdAt: msg.createdAt,
      editedAt: msg.editedAt,
      isMine: mine,
      // Own outgoing starts as sent (single ✓), not read/delivered.
      isDelivered: mine ? false : msg.isDelivered,
      isRead: mine ? false : msg.isRead,
      readCount: mine ? 0 : msg.readCount,
      disableWebpagePreview: msg.disableWebpagePreview,
      reactions: msg.reactions,
      inlineKeyboard: msg.inlineKeyboard,
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

  /// Exact @username lookup for deep links. Returns null when not found.
  static Future<ChatUserBrief?> resolveUsername(String username) async {
    final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (handle.length < 2) return null;
    final uri = Uri.parse(
      '$_base/users/by-username/${Uri.encodeComponent(handle)}',
    );
    final response = await _get(uri);
    if (response.statusCode == 404) return null;
    _ensureOk(response, 'Не удалось найти пользователя');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatUserBrief.fromJson(data);
  }

  /// Shared media / links for a conversation (full history, paginated).
  static Future<({List<ChatMessage> items, bool hasMore, int? nextCursor})>
      listChatMedia({
    required int conversationId,
    String kind = 'all',
    int? cursor,
    int? senderId,
    int limit = 60,
  }) async {
    final uri = Uri.parse('$_base/chats/$conversationId/media').replace(
      queryParameters: {
        'kind': kind,
        if (cursor != null) 'cursor': '$cursor',
        if (senderId != null) 'sender_id': '$senderId',
        'limit': '$limit',
      },
    );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось загрузить медиа чата');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      items: items,
      hasMore: data['has_more'] as bool? ?? false,
      nextCursor: data['next_cursor'] as int?,
    );
  }

  static Future<List<ChatMessageSearchItem>> searchMessages({
    required String query,
    int? conversationId,
    String? type,
    int? senderId,
    int limit = 40,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = conversationId == null
        ? Uri.parse('$_base/chats/messages/search').replace(
            queryParameters: {
              'q': q,
              if (type != null && type.isNotEmpty) 'type': type,
              if (senderId != null) 'sender_id': '$senderId',
              'limit': '$limit',
            },
          )
        : Uri.parse('$_base/chats/$conversationId/messages/search').replace(
            queryParameters: {
              'q': q,
              if (type != null && type.isNotEmpty) 'type': type,
              if (senderId != null) 'sender_id': '$senderId',
              'limit': '$limit',
            },
          );
    final response = await _get(uri);
    _ensureOk(response, 'Не удалось выполнить поиск по сообщениям');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final out = <ChatMessageSearchItem>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        out.add(ChatMessageSearchItem.fromJson(raw));
      } catch (_) {}
    }
    return out;
  }

  static ChatFolder _folderFromResponse(
      http.Response response, String fallback) {
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
