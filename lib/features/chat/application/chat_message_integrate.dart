import '../../../models/chat_models.dart';

class ChatMessageIntegrateResult {
  const ChatMessageIntegrateResult({
    required this.messages,
    required this.added,
  });

  final List<ChatMessage> messages;
  final bool added;
}

/// Merge a confirmed/incoming message without wiping other in-flight bubbles.
///
/// Telegram-like: optimistic outgoing stays until *this* message is matched
/// (temp id, client_message_id, or a single content duplicate).
ChatMessageIntegrateResult integrateIncomingChatMessage({
  required List<ChatMessage> messages,
  required ChatMessage incoming,
  int? removeTempId,
  required bool Function(ChatMessage local, ChatMessage incoming) isDuplicate,
  required ChatMessage Function(ChatMessage local, ChatMessage incoming) merge,
}) {
  final next = List<ChatMessage>.from(messages);
  if (removeTempId != null) {
    next.removeWhere((m) => m.id == removeTempId);
  }

  final clientKey = (incoming.clientMessageId ?? '').trim();
  var matchIdx = -1;
  if (clientKey.isNotEmpty) {
    matchIdx = next.indexWhere(
      (m) => (m.clientMessageId ?? '').trim() == clientKey,
    );
  }
  if (matchIdx < 0 && incoming.id > 0) {
    matchIdx = next.indexWhere((m) => m.id > 0 && m.id == incoming.id);
  }
  if (matchIdx < 0) {
    matchIdx = next.indexWhere((m) => isDuplicate(m, incoming));
  }

  if (matchIdx >= 0) {
    next[matchIdx] = merge(next[matchIdx], incoming);
    return ChatMessageIntegrateResult(messages: next, added: false);
  }

  next.add(incoming);
  return ChatMessageIntegrateResult(messages: next, added: true);
}

/// Keep unconfirmed outgoing bubbles across a full thread reload.
List<ChatMessage> preserveOptimisticOutgoing({
  required List<ChatMessage> previous,
  required List<ChatMessage> serverItems,
  required Set<int> keepTempIds,
  required bool Function(ChatMessage local, ChatMessage incoming) isDuplicate,
}) {
  final serverIds = {for (final m in serverItems) if (m.id > 0) m.id};
  var maxServerId = 0;
  for (final id in serverIds) {
    if (id > maxServerId) maxServerId = id;
  }
  final kept = <ChatMessage>[];
  for (final local in previous) {
    if (local.id > 0) {
      if (serverIds.contains(local.id)) continue;
      // Just-sent row not in the snapshot yet (replica / race).
      if (local.isMine && local.id > maxServerId) {
        kept.add(local);
      }
      continue;
    }
    if (!keepTempIds.contains(local.id)) continue;
    final already = serverItems.any(
      (incoming) =>
          isDuplicate(local, incoming) ||
          ((local.clientMessageId ?? '').isNotEmpty &&
              local.clientMessageId == incoming.clientMessageId),
    );
    if (!already) kept.add(local);
  }
  if (kept.isEmpty) return serverItems;
  return [...serverItems, ...kept];
}
