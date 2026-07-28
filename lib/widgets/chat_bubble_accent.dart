import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Per-chat outgoing bubble color (Telegram-style local theme accent).
enum ChatBubbleAccent {
  defaultAccent,
  mint,
  sky,
  rose,
  amber,
  slate,
  grape;

  static const defaultStyle = ChatBubbleAccent.defaultAccent;

  String get id {
    switch (this) {
      case ChatBubbleAccent.defaultAccent:
        return 'default';
      case ChatBubbleAccent.mint:
        return 'mint';
      case ChatBubbleAccent.sky:
        return 'sky';
      case ChatBubbleAccent.rose:
        return 'rose';
      case ChatBubbleAccent.amber:
        return 'amber';
      case ChatBubbleAccent.slate:
        return 'slate';
      case ChatBubbleAccent.grape:
        return 'grape';
    }
  }

  String get label {
    switch (this) {
      case ChatBubbleAccent.defaultAccent:
        return 'По умолчанию';
      case ChatBubbleAccent.mint:
        return 'Мята';
      case ChatBubbleAccent.sky:
        return 'Небо';
      case ChatBubbleAccent.rose:
        return 'Роза';
      case ChatBubbleAccent.amber:
        return 'Янтарь';
      case ChatBubbleAccent.slate:
        return 'Сланец';
      case ChatBubbleAccent.grape:
        return 'Виноград';
    }
  }

  static ChatBubbleAccent fromId(String? raw) {
    final id = (raw ?? '').trim().toLowerCase();
    if (id.isEmpty || id == 'default') return defaultStyle;
    for (final accent in ChatBubbleAccent.values) {
      if (accent.id == id) return accent;
    }
    return defaultStyle;
  }

  Color outgoingColor({required bool isDark}) {
    switch (this) {
      case ChatBubbleAccent.defaultAccent:
        return isDark
            ? AppColors.telegramOutgoingDark
            : AppColors.telegramOutgoingLight;
      case ChatBubbleAccent.mint:
        return isDark ? const Color(0xFF1F4A3A) : const Color(0xFFD7F5E9);
      case ChatBubbleAccent.sky:
        return isDark ? const Color(0xFF1E3A55) : const Color(0xFFD7EAF8);
      case ChatBubbleAccent.rose:
        return isDark ? const Color(0xFF4A2A35) : const Color(0xFFF8DDE4);
      case ChatBubbleAccent.amber:
        return isDark ? const Color(0xFF4A3820) : const Color(0xFFF8EBD0);
      case ChatBubbleAccent.slate:
        return isDark ? const Color(0xFF2A3340) : const Color(0xFFE2E7EE);
      case ChatBubbleAccent.grape:
        return isDark ? const Color(0xFF3A2F48) : const Color(0xFFE8DFEF);
    }
  }

  Color swatchColor({required bool isDark}) =>
      outgoingColor(isDark: isDark);
}
