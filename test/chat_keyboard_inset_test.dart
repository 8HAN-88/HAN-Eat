import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_keyboard_inset.dart';

void main() {
  group('effectiveChatKeyboardInset', () {
    test('ignores rubber-band chrome when composer is closed', () {
      expect(
        effectiveChatKeyboardInset(rawInset: 24, composerFocused: false),
        0,
      );
      expect(
        effectiveChatKeyboardInset(rawInset: 79, composerFocused: true),
        0,
      );
    });

    test('keeps a real keyboard inset', () {
      expect(
        effectiveChatKeyboardInset(rawInset: 336, composerFocused: true),
        336,
      );
    });
  });

  group('chatBottomFabPolicy', () {
    test('hides at the bottom and shows only after leaving the bounce zone', () {
      expect(
        chatBottomFabPolicy(offset: 1000, maxScrollExtent: 1000),
        ChatBottomFabPolicy.hide,
      );
      expect(
        chatBottomFabPolicy(offset: 900, maxScrollExtent: 1000),
        ChatBottomFabPolicy.keep,
      );
      expect(
        chatBottomFabPolicy(offset: 800, maxScrollExtent: 1000),
        ChatBottomFabPolicy.show,
      );
    });
  });
}
