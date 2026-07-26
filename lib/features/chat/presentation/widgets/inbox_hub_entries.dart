import '../../../../models/chat_models.dart';
import '../../../../services/channel_service.dart';

sealed class InboxHubEntry {
  DateTime get sortAt;
}

class ChatInboxEntry extends InboxHubEntry {
  ChatInboxEntry(this.chat);

  final ChatConversation chat;

  @override
  DateTime get sortAt => chat.updatedAt;
}

class ChannelInboxEntry extends InboxHubEntry {
  ChannelInboxEntry({
    required this.channel,
    this.isFavorite = false,
    this.notificationsEnabled = true,
  }) : sortAt = channel.lastPostAt ?? channel.createdAt;

  final Channel channel;
  final bool isFavorite;
  final bool notificationsEnabled;

  bool get muted => !notificationsEnabled;

  @override
  DateTime sortAt;
}
