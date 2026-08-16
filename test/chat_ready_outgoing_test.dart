import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_ready_outgoing.dart';
import 'package:han_eat/models/chat_poll.dart';

void main() {
  test('optimistic poll content renders as a real poll bubble', () {
    final raw = optimisticPollContent(
      question: 'Обед?',
      description: 'выберите',
      options: const ['Суп', 'Салат'],
      settings: const ChatPollSettings(quizMode: false).toJson(),
    );
    final poll = parseChatPollFromContent(raw);
    expect(poll, isNotNull);
    expect(poll!.question, 'Обед?');
    expect(poll.options.map((o) => o.text), ['Суп', 'Салат']);
    expect(poll.totalVotes, 0);
  });

  test('ready outgoing json round-trips sticker fields', () {
    final pending = ChatReadyOutgoing(
      tempId: -12,
      clientMessageId: 'sticker-1',
      type: 'sticker',
      content: '😀',
      mediaUrl: 'https://cdn.example/s.webp',
      topicId: 4,
      anonymous: true,
    );
    final again = ChatReadyOutgoing.fromJson(pending.toJson());
    expect(again.tempId, -12);
    expect(again.clientMessageId, 'sticker-1');
    expect(again.type, 'sticker');
    expect(again.mediaUrl, 'https://cdn.example/s.webp');
    expect(again.topicId, 4);
    expect(again.anonymous, isTrue);
  });

  test('ready outgoing json keeps video and voice fields', () {
    final video = ChatReadyOutgoing.fromJson(
      ChatReadyOutgoing(
        tempId: -3,
        clientMessageId: 'vid-1',
        type: 'video',
        content: 'cap',
        mediaUrl: 'https://cdn.example/v.mp4',
      ).toJson(),
    );
    expect(video.type, 'video');
    expect(video.mediaUrl, 'https://cdn.example/v.mp4');
    final voice = ChatReadyOutgoing.fromJson(
      ChatReadyOutgoing(
        tempId: -4,
        clientMessageId: 'voice-1',
        type: 'voice',
        content: '3',
        mediaUrl: 'https://cdn.example/a.m4a',
        durationSec: 3,
      ).toJson(),
    );
    expect(voice.type, 'voice');
    expect(voice.durationSec, 3);
  });

  test('ready outgoing json keeps story reply and live location', () {
    final story = ChatReadyOutgoing.fromJson(
      ChatReadyOutgoing(
        tempId: -8,
        clientMessageId: 'story-1',
        type: 'story_reply',
        content: '{"story_id":1,"text":"hi","author_id":2}',
        mediaUrl: 'https://cdn.example/s.jpg',
      ).toJson(),
    );
    expect(story.type, 'story_reply');
    expect(story.mediaUrl, 'https://cdn.example/s.jpg');
    final live = ChatReadyOutgoing.fromJson(
      ChatReadyOutgoing(
        tempId: -9,
        clientMessageId: 'live-1',
        type: 'live_location',
        content: '📍 Геопозиция',
        durationSec: 900,
        latitude: 55.75,
        longitude: 37.61,
      ).toJson(),
    );
    expect(live.type, 'live_location');
    expect(live.durationSec, 900);
    expect(live.latitude, 55.75);
    expect(live.longitude, 37.61);
  });

  test('new ready temp ids are local (negative)', () {
    expect(newReadyOutgoingTempId(), lessThan(0));
  });
}
