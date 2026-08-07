// Telegram-like "Reply privately" seed for opening a DM with a quote strip.

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
String composeTextWithPrivateReply(String text, ChatPrivateReplyQuote quote) {
  final body = text.trim();
  final who = quote.author.trim().isEmpty ? 'Участник' : quote.author.trim();
  var clipped = quote.preview.trim();
  if (clipped.length > 180) {
    clipped = '${clipped.substring(0, 180)}…';
  }
  final header = clipped.isEmpty ? '↩️ $who' : '↩️ $who: $clipped';
  if (body.isEmpty) return header;
  return '$header\n\n$body';
}
