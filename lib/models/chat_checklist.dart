import 'dart:convert';

import '../services/custom_emoji_registry.dart';

class ChatChecklistItem {
  const ChatChecklistItem({required this.text, this.done = false});

  final String text;
  final bool done;
}

class ChatChecklist {
  const ChatChecklist({required this.title, required this.items});

  final String title;
  final List<ChatChecklistItem> items;

  int get doneCount => items.where((item) => item.done).length;

  String get preview =>
      '☑ ${previewTextWithCustomEmoji(title)} ($doneCount/${items.length})';

  factory ChatChecklist.fromJson(Map<String, dynamic> json) {
    final raw = json['checklist'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('checklist');
    }
    final items = <ChatChecklistItem>[];
    for (final row in raw['items'] as List<dynamic>? ?? const []) {
      if (row is! Map<String, dynamic>) continue;
      final text = (row['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      items.add(ChatChecklistItem(text: text, done: row['done'] == true));
    }
    return ChatChecklist(
      title: (raw['title'] as String? ?? '').trim(),
      items: items,
    );
  }

  String encode() => jsonEncode({
        'checklist': {
          'title': title,
          'items': [
            for (final item in items) {'text': item.text, 'done': item.done},
          ],
        },
      });

  ChatChecklist toggled(int index, bool done) {
    return ChatChecklist(
      title: title,
      items: [
        for (var i = 0; i < items.length; i++)
          ChatChecklistItem(
            text: items[i].text,
            done: i == index ? done : items[i].done,
          ),
      ],
    );
  }

  static ChatChecklist? tryParse(String? content) {
    if (content == null || content.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final parsed = ChatChecklist.fromJson(decoded);
      if (parsed.title.isEmpty || parsed.items.isEmpty) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
}

class ChatChecklistDraft {
  const ChatChecklistDraft({required this.title, required this.items});

  final String title;
  final List<String> items;

  String get optimisticContent => ChatChecklist(
        title: title,
        items: [for (final text in items) ChatChecklistItem(text: text)],
      ).encode();
}

String profileColorHex(String? key) {
  switch (key) {
    case 'blue':
      return '#3390EC';
    case 'red':
      return '#E53935';
    case 'orange':
      return '#FB8C00';
    case 'green':
      return '#43A047';
    case 'cyan':
      return '#00ACC1';
    case 'purple':
      return '#8E24AA';
    case 'pink':
      return '#D81B60';
    case 'navy':
      return '#1565C0';
    default:
      return '';
  }
}

const profileColorKeys = <String>[
  'blue',
  'red',
  'orange',
  'green',
  'cyan',
  'purple',
  'pink',
  'navy',
];
