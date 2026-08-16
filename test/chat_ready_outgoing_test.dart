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
}
