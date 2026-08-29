import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/channels/application/channel_posts_phase.dart';

void main() {
  test('first paint with no posts is loading, not empty', () {
    expect(
      channelPostsPhase(hasPosts: false, isLoading: true),
      ChannelPostsPhase.loading,
    );
  });

  test('empty only after load finished without posts', () {
    expect(
      channelPostsPhase(hasPosts: false, isLoading: false),
      ChannelPostsPhase.empty,
    );
  });

  test('error wins over empty when load failed', () {
    expect(
      channelPostsPhase(
        hasPosts: false,
        isLoading: false,
        error: 'fail',
      ),
      ChannelPostsPhase.error,
    );
  });

  test('existing posts stay visible during refresh', () {
    expect(
      channelPostsPhase(hasPosts: true, isLoading: true),
      ChannelPostsPhase.list,
    );
  });
}
