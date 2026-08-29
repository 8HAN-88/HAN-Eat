import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/inbox_cache_keep.dart';

void main() {
  test('keeps cached inbox when fetch is empty', () {
    expect(
      keepStaleInboxOnEmptyFetch(
        hasLocalInbox: true,
        fetchReturnedItems: false,
      ),
      isTrue,
    );
  });

  test('does not keep empty inbox', () {
    expect(
      keepStaleInboxOnEmptyFetch(
        hasLocalInbox: false,
        fetchReturnedItems: false,
      ),
      isFalse,
    );
  });

  test('fresh fetch replaces cache', () {
    expect(
      keepStaleInboxOnEmptyFetch(
        hasLocalInbox: true,
        fetchReturnedItems: true,
      ),
      isFalse,
    );
  });
}
