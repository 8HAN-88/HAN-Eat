import 'package:flutter/material.dart';

class ChatInboxTag {
  const ChatInboxTag({
    required this.id,
    required this.title,
    required this.color,
    this.sortOrder = 0,
  });

  final int id;
  final String title;
  final String color;
  final int sortOrder;

  factory ChatInboxTag.fromJson(Map<String, dynamic> json) {
    return ChatInboxTag(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      color: json['color'] as String? ?? 'blue',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

Color chatTagColor(String key, ColorScheme scheme) {
  switch (key) {
    case 'red':
      return const Color(0xFFE53935);
    case 'orange':
      return const Color(0xFFFB8C00);
    case 'yellow':
      return const Color(0xFFFDD835);
    case 'green':
      return const Color(0xFF43A047);
    case 'cyan':
      return const Color(0xFF00ACC1);
    case 'purple':
      return const Color(0xFF8E24AA);
    case 'pink':
      return const Color(0xFFD81B60);
    case 'blue':
    default:
      return scheme.primary;
  }
}

const chatTagColorKeys = [
  'red',
  'orange',
  'yellow',
  'green',
  'cyan',
  'blue',
  'purple',
  'pink',
];
