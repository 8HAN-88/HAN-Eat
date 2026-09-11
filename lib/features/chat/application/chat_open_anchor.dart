import 'package:flutter/widgets.dart';

/// Where Telegram opens a chat: last message, first unread, or a specific id.
enum ChatOpenKind { bottom, unread, message }

class ChatOpenTarget {
  const ChatOpenTarget({required this.kind, this.messageId});

  final ChatOpenKind kind;
  final int? messageId;

  bool get isBottom => kind == ChatOpenKind.bottom;

  /// 0 = oldest, 1 = latest. Used to pin the list before the first paint.
  double fractionFor({required int? messageIndex, required int length}) {
    if (isBottom || length <= 1 || messageIndex == null) return 1;
    if (messageIndex < 0) return 1;
    return (messageIndex / (length - 1)).clamp(0.0, 1.0);
  }
}

/// Deep-link > first unread > saved mid-history > last message.
ChatOpenTarget resolveChatOpenTarget({
  int? jumpToMessageId,
  int? firstUnreadId,
  int? savedMessageId,
}) {
  final jump = jumpToMessageId ?? 0;
  if (jump > 0) {
    return ChatOpenTarget(kind: ChatOpenKind.message, messageId: jump);
  }
  final unread = firstUnreadId ?? 0;
  if (unread > 0) {
    return ChatOpenTarget(kind: ChatOpenKind.unread, messageId: unread);
  }
  final saved = savedMessageId ?? 0;
  if (saved > 0) {
    return ChatOpenTarget(kind: ChatOpenKind.message, messageId: saved);
  }
  return const ChatOpenTarget(kind: ChatOpenKind.bottom);
}

int? firstUnreadMessageId({
  required int unreadCount,
  required List<({int id, bool isMine})> messagesOldestFirst,
}) {
  if (unreadCount <= 0 || messagesOldestFirst.isEmpty) return null;
  var remaining = unreadCount;
  for (var i = messagesOldestFirst.length - 1; i >= 0; i--) {
    if (messagesOldestFirst[i].isMine) continue;
    remaining--;
    if (remaining <= 0) return messagesOldestFirst[i].id;
  }
  return messagesOldestFirst.first.id;
}

/// Pins the thread to [openFraction] during layout so the first frame is
/// already on the last (or unread) messages — not the top of history.
class ChatThreadScrollController extends ScrollController {
  ChatThreadScrollController();

  double openFraction = 1;
  bool holdOpenAnchor = true;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return ChatThreadScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      controller: this,
    );
  }
}

class ChatThreadScrollPosition extends ScrollPositionWithSingleContext {
  ChatThreadScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.controller,
  });

  final ChatThreadScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (controller.holdOpenAnchor && maxScrollExtent > minScrollExtent) {
      final t = controller.openFraction.clamp(0.0, 1.0);
      correctPixels(
        minScrollExtent + (maxScrollExtent - minScrollExtent) * t,
      );
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
