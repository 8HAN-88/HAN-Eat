import '../../../services/channel_service.dart';

/// Счётчик «новых постов» в каналах (с сервера, синхронизация между устройствами).
class ChannelInboxBadge {
  static Future<int> countNewPosts() async {
    try {
      final owned = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        mine: true,
      );
      final subscribed = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        subscribed: true,
      );
      final seen = <int>{};
      var total = 0;
      for (final c in [...owned.items, ...subscribed.items]) {
        if (!seen.add(c.id)) continue;
        total += c.inboxUnreadPosts;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
