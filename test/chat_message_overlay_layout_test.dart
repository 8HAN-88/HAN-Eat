import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_message_action_overlay.dart';

void main() {
  const screen = Size(390, 844);
  const padding = EdgeInsets.only(top: 47, bottom: 34);

  test('bottom message: menu anchored above composer', () {
    final layout = ChatMessageOverlayLayout.compute(
      messageRect: const Rect.fromLTWH(220, 620, 140, 44),
      screenSize: screen,
      padding: padding,
      menuItemCount: 7,
      hasDivider: true,
      reactionCount: 7,
      isOutgoing: true,
      bottomComposerReserve: 88,
    );

    const menuItemCount = 7;
    const menuH = menuItemCount * 46 + 8;
    final maxMenuBottom = screen.height - padding.bottom - 88;
    expect(layout.menuTop + menuH, lessThanOrEqualTo(maxMenuBottom + 1));
    expect(layout.messageTop, lessThan(620));
  });

  test('outgoing: menu aligned to message right edge', () {
    const messageLeft = 200.0;
    const messageWidth = 150.0;
    const menuWidth = 260.0;
    final layout = ChatMessageOverlayLayout.compute(
      messageRect: Rect.fromLTWH(messageLeft, 300, messageWidth, 40),
      screenSize: screen,
      padding: padding,
      menuItemCount: 5,
      hasDivider: false,
      reactionCount: 7,
      isOutgoing: true,
    );

    expect(layout.menuLeft + menuWidth, closeTo(messageLeft + messageWidth, 1));
  });

  test('incoming: menu left-aligned with bubble', () {
    const messageLeft = 16.0;
    final layout = ChatMessageOverlayLayout.compute(
      messageRect: const Rect.fromLTWH(messageLeft, 300, 180, 40),
      screenSize: screen,
      padding: padding,
      menuItemCount: 5,
      hasDivider: false,
      reactionCount: 7,
      isOutgoing: false,
    );

    expect(layout.menuLeft, messageLeft);
  });

  test('cluster order: reactions above message, menu below', () {
    const messageH = 40.0;
    final layout = ChatMessageOverlayLayout.compute(
      messageRect: const Rect.fromLTWH(200, 400, 140, messageH),
      screenSize: screen,
      padding: padding,
      menuItemCount: 6,
      hasDivider: true,
      reactionCount: 7,
      isOutgoing: true,
    );

    expect(layout.reactionTop, lessThan(layout.messageTop));
    expect(layout.messageTop + messageH, lessThan(layout.menuTop));
  });
}
