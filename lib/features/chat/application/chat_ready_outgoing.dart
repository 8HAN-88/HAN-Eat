import 'dart:convert';

import '../../../models/chat_models.dart';
import '../../../models/chat_poll.dart';
import '../../../services/chat_service.dart';

/// Already-ready outgoing payload (sticker, GIF, location, contact, poll…).
/// Shown instantly, then flushed with [clientMessageId] like Telegram.
class ChatReadyOutgoing {
  ChatReadyOutgoing({
    required this.tempId,
    required this.clientMessageId,
    required this.type,
    required this.content,
    this.mediaUrl,
    this.replyToMessageId,
    this.silent = false,
    this.topicId,
    this.anonymous = false,
    this.pollQuestion,
    this.pollDescription,
    this.pollOptions,
    this.pollSettings,
    this.fileName,
    this.durationSec,
  });

  final int tempId;
  final String clientMessageId;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? replyToMessageId;
  final bool silent;
  final int? topicId;
  final bool anonymous;
  final String? pollQuestion;
  final String? pollDescription;
  final List<String>? pollOptions;
  final Map<String, dynamic>? pollSettings;
  final String? fileName;
  final int? durationSec;
  int attempts = 0;

  Map<String, dynamic> toJson() => {
        'temp_id': tempId,
        'client_message_id': clientMessageId,
        'type': type,
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        'silent': silent,
        if (topicId != null) 'topic_id': topicId,
        'anonymous': anonymous,
        if (pollQuestion != null) 'poll_question': pollQuestion,
        if (pollDescription != null) 'poll_description': pollDescription,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (pollSettings != null) 'poll_settings': pollSettings,
        if (fileName != null) 'file_name': fileName,
        if (durationSec != null) 'duration_sec': durationSec,
        'attempts': attempts,
      };

  factory ChatReadyOutgoing.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw');
    }

    final optionsRaw = json['poll_options'];
    final pending = ChatReadyOutgoing(
      tempId: asInt(json['temp_id']) ?? 0,
      clientMessageId: json['client_message_id'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      replyToMessageId: asInt(json['reply_to_message_id']),
      silent: json['silent'] == true,
      topicId: asInt(json['topic_id']),
      anonymous: json['anonymous'] == true,
      pollQuestion: json['poll_question'] as String?,
      pollDescription: json['poll_description'] as String?,
      pollOptions: optionsRaw is List
          ? optionsRaw.map((e) => e.toString()).toList()
          : null,
      pollSettings: json['poll_settings'] is Map
          ? Map<String, dynamic>.from(json['poll_settings'] as Map)
          : null,
      fileName: json['file_name'] as String?,
      durationSec: asInt(json['duration_sec']),
    );
    pending.attempts = json['attempts'] as int? ?? 0;
    return pending;
  }
}

/// Local poll JSON so the optimistic bubble renders immediately.
String optimisticPollContent({
  required String question,
  String description = '',
  required List<String> options,
  Map<String, dynamic>? settings,
}) {
  return jsonEncode({
    'poll': {
      'question': question,
      'description': description,
      'options': [
        for (var i = 0; i < options.length; i++)
          {'index': i, 'text': options[i], 'votes': 0, 'percentage': 0},
      ],
      'settings': settings ?? const ChatPollSettings().toJson(),
      'is_closed': false,
      'total_votes': 0,
      'voted_option_indices': <int>[],
    },
  });
}

Future<ChatMessage> sendChatReadyOutgoing({
  required int conversationId,
  required ChatReadyOutgoing pending,
}) {
  switch (pending.type) {
    case 'sticker':
      return ChatService.sendSticker(
        conversationId: conversationId,
        mediaUrl: pending.mediaUrl ?? '',
        emoji: pending.content,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
    case 'image':
      return ChatService.sendImage(
        conversationId: conversationId,
        mediaUrl: pending.mediaUrl ?? '',
        caption: pending.content,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
    case 'file':
      return ChatService.sendFile(
        conversationId: conversationId,
        mediaUrl: pending.mediaUrl ?? '',
        fileName: pending.fileName ?? pending.content,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
    case 'video_note':
      return ChatService.sendVideoNote(
        conversationId: conversationId,
        mediaUrl: pending.mediaUrl ?? '',
        durationSec: pending.durationSec ?? 1,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
    case 'location':
      return ChatService.sendLocation(
        conversationId: conversationId,
        content: pending.content,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
    case 'poll':
      return ChatService.sendPoll(
        conversationId: conversationId,
        question: pending.pollQuestion ?? pending.content,
        description: pending.pollDescription ?? '',
        options: pending.pollOptions ?? const [],
        settings: pending.pollSettings,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
      );
    default:
      return ChatService.sendText(
        conversationId: conversationId,
        content: pending.content,
        replyToMessageId: pending.replyToMessageId,
        clientMessageId: pending.clientMessageId,
        silent: pending.silent,
        topicId: pending.topicId,
        anonymous: pending.anonymous,
      );
  }
}
