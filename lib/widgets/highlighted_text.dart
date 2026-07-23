import 'package:flutter/material.dart';

/// Текст с подсветкой совпадений поиска и/или @mentions.
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
    this.highlightMentions = false,
    this.mentionColor,
  });

  final String text;
  final String? query;
  final TextStyle style;
  final Color? highlightColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? trailingReserveWidth;
  final bool highlightMentions;
  final Color? mentionColor;

  static final _mentionRe = RegExp(r'@[a-zA-Z0-9_]{2,}');

  InlineSpan? get _trailingReserve {
    final w = trailingReserveWidth;
    if (w == null || w <= 0) return null;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SizedBox(width: w, height: 1),
    );
  }

  List<InlineSpan> _mentionSpans(BuildContext context, String source) {
    final mentionStyle = style.copyWith(
      color: mentionColor ?? Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _mentionRe.allMatches(source)) {
      if (m.start > start) {
        spans.add(TextSpan(text: source.substring(start, m.start)));
      }
      spans.add(TextSpan(text: m.group(0), style: mentionStyle));
      start = m.end;
    }
    if (start < source.length) {
      spans.add(TextSpan(text: source.substring(start)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final reserve = _trailingReserve;
    final q = query?.trim().toLowerCase();
    final hasQuery = q != null && q.isNotEmpty;

    if (!hasQuery && !highlightMentions) {
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

    final spans = <InlineSpan>[];

    if (hasQuery) {
      final lower = text.toLowerCase();
      var start = 0;
      while (true) {
        final index = lower.indexOf(q, start);
        if (index < 0) {
          if (start < text.length) {
            final rest = text.substring(start);
            if (highlightMentions) {
              spans.addAll(_mentionSpans(context, rest));
            } else {
              spans.add(TextSpan(text: rest));
            }
          }
          break;
        }
        if (index > start) {
          final chunk = text.substring(start, index);
          if (highlightMentions) {
            spans.addAll(_mentionSpans(context, chunk));
          } else {
            spans.add(TextSpan(text: chunk));
          }
        }
        spans.add(
          TextSpan(
            text: text.substring(index, index + q.length),
            style: style.copyWith(
              backgroundColor: highlightColor ??
                  Theme.of(context)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        start = index + q.length;
      }
    } else {
      spans.addAll(_mentionSpans(context, text));
    }

    if (reserve != null) spans.add(reserve);

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
