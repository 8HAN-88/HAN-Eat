import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/channel_cache_service.dart';

void main() {
  test('peek helpers are empty before a channel is warmed', () {
    expect(ChannelCacheService.peekChannel(424242), isNull);
    expect(ChannelCacheService.peekPosts(channelId: 424242), isNull);
  });
}
