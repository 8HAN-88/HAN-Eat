import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_thread_prefetch.dart';
import 'package:han_eat/models/chat_models.dart';

ChatThreadPrefetchPage _page({required DateTime fetchedAt}) {
  return ChatThreadPrefetchPage(
    items: [
      ChatMessage(
        id: 11,
        conversationId: 7,
        senderId: 3,
        type: 'text',
        content: 'hi',
        createdAt: DateTime(2026, 8, 16, 12),
      ),
    ],
    hasMore: true,
    nextCursor: 4,
    pinnedMessages: const [],
    fetchedAt: fetchedAt,
  );
}

void main() {
  setUp(ChatThreadPrefetch.debugReset);
  tearDown(ChatThreadPrefetch.debugReset);

  test('takeFresh returns a page still inside the window', () {
    final page = _page(fetchedAt: DateTime.now());
    ChatThreadPrefetch.debugSeed(7, page);
    final fresh = ChatThreadPrefetch.takeFresh(7);
    expect(fresh, isNotNull);
    expect(fresh!.items.single.id, 11);
    expect(fresh.hasMore, isTrue);
    expect(fresh.nextCursor, 4);
  });

  test('takeFresh ignores a stale page', () {
    ChatThreadPrefetch.debugSeed(
      7,
      _page(
        fetchedAt: DateTime.now().subtract(const Duration(seconds: 4)),
      ),
    );
    expect(ChatThreadPrefetch.takeFresh(7), isNull);
  });

  test('page joins the in-flight future instead of starting another fetch',
      () async {
    final completer = Completer<ChatThreadPrefetchPage?>();
    ChatThreadPrefetch.debugSetInFlight(7, completer.future);
    final first = ChatThreadPrefetch.page(7);
    final second = ChatThreadPrefetch.page(7);
    expect(identical(first, second), isTrue);
    final seeded = _page(fetchedAt: DateTime.now());
    completer.complete(seeded);
    expect(await first, same(seeded));
    expect(await second, same(seeded));
  });

  test('page(0) is a no-op', () async {
    expect(await ChatThreadPrefetch.page(0), isNull);
    expect(ChatThreadPrefetch.inFlight(0), isNull);
  });
}
