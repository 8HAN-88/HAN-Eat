import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_private_reply.dart';

void main() {
  group('composeTextWithPrivateReply', () {
    const quote = ChatPrivateReplyQuote(
      sourceConversationId: 1,
      sourceMessageId: 2,
      author: 'Anna',
      preview: 'Hello there',
      sourceChatTitle: 'Team',
    );

    test('embeds quote above body', () {
      expect(
        composeTextWithPrivateReply('Sure', quote),
        '↩️ Anna: Hello there\n\nSure',
      );
    });

    test('clips long preview', () {
      final long = ChatPrivateReplyQuote(
        sourceConversationId: 1,
        sourceMessageId: 2,
        author: 'Bob',
        preview: 'x' * 200,
      );
      final out = composeTextWithPrivateReply('ok', long);
      expect(out.startsWith('↩️ Bob: ${'x' * 180}…'), isTrue);
      expect(out.endsWith('\n\nok'), isTrue);
    });

    test('stripAuthor includes chat title', () {
      expect(quote.stripAuthor, 'Anna · Team');
    });

    test('previews custom emoji in peer author name', () {
      const named = ChatPrivateReplyQuote(
        sourceConversationId: 1,
        sourceMessageId: 2,
        author: 'Anna [[e:1]]',
        preview: 'Hello there',
      );
      expect(
        composeTextWithPrivateReply('Sure', named),
        '↩️ Anna ✦: Hello there\n\nSure',
      );
    });

    test('previews custom emoji in quoted preview', () {
      const quoted = ChatPrivateReplyQuote(
        sourceConversationId: 1,
        sourceMessageId: 2,
        author: 'Anna',
        preview: 'Hello [[e:1]]',
      );
      expect(
        composeTextWithPrivateReply('Sure', quoted),
        '↩️ Anna: Hello ✦\n\nSure',
      );
    });
  });
}
