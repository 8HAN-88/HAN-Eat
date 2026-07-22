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
    /// Invisible trailing space so bubble meta (time/ticks) can sit on the
    /// last line like Telegram.
    this.trailingReserveWidth,
  });

  final String text;
  final String? query;
  final TextStyle style;
  final Color? highlightColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? trailingReserveWidth;

  InlineSpan? get _trailingReserve {
    final w = trailingReserveWidth;
    if (w == null || w <= 0) return null;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SizedBox(width: w, height: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reserve = _trailingReserve;
    final q = query?.trim().toLowerCase();
    if (q == null || q.isEmpty) {
      if (reserve == null) {
        return Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      }
      return Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: text),
            reserve,
          ],
        ),
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final lower = text.toLowerCase();
    final spans = <InlineSpan>[];
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
    if (reserve != null) spans.add(reserve);

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
