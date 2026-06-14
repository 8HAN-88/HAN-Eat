import 'package:flutter/material.dart';

/// Текст с подсветкой совпадений поиска.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    this.query,
    required this.style,
    this.highlightColor,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String? query;
  final TextStyle style;
  final Color? highlightColor;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final q = query?.trim().toLowerCase();
    if (q == null || q.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: style.copyWith(
            backgroundColor: highlightColor ??
                Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + q.length;
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
