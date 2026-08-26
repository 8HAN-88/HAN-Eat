// Telegram-like "Reply privately" seed for opening a DM with a quote strip.

import '../../../services/custom_emoji_registry.dart';

class ChatPrivateReplyQuote {
  const ChatPrivateReplyQuote({
    required this.sourceConversationId,
    required this.sourceMessageId,
    required this.author,
    required this.preview,
    this.sourceChatTitle,
  });

  final int sourceConversationId;
  final int sourceMessageId;
  final String author;
  final String preview;
  final String? sourceChatTitle;

  String get stripAuthor {
    final title = sourceChatTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return '$author · $title';
    }
    return author;
  }
}

/// Embeds a private-reply quote into outgoing text (no cross-chat reply_to yet).
///
/// Author name and quoted preview are peer texts — preview tokens so a
/// user without custom_emoji (69) is not 403'd for someone else's `[[e:id]]`.
String composeTextWithPrivateReply(String text, ChatPrivateReplyQuote quote) {
  final body = text.trim();
  final rawWho = quote.author.trim();
  final who = rawWho.isEmpty
      ? 'Участник'
      : previewTextWithCustomEmoji(rawWho);
  final rawPreview = quote.preview.trim();
  var clipped = rawPreview.isEmpty
      ? ''
      : previewTextWithCustomEmoji(rawPreview);
  if (clipped.length > 180) {
    clipped = '${clipped.substring(0, 180)}…';
  }
  final header = clipped.isEmpty ? '↩️ $who' : '↩️ $who: $clipped';
  if (body.isEmpty) return header;
  return '$header\n\n$body';
}
