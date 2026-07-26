import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Текст с подсветкой поиска, @mentions и лёгкой разметкой
/// (`||spoiler||`, `*bold*`, `_italic_`, `` `code` ``).
class HighlightedText extends StatefulWidget {
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
    this.onMentionTap,
    this.parseMarkup = false,
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
  final ValueChanged<String>? onMentionTap;
  final bool parseMarkup;

  @override
  State<HighlightedText> createState() => _HighlightedTextState();
}

class _HighlightedTextState extends State<HighlightedText> {
  final Set<int> _revealedSpoilers = {};

  static final _mentionRe = RegExp(r'@[a-zA-Z0-9_]{2,}');
  static final _markupRe = RegExp(
    r'\|\|(.+?)\|\|'
    r'|\*(.+?)\*'
    r'|_(.+?)_'
    r'|`([^`]+)`',
    dotAll: true,
  );

  InlineSpan? get _trailingReserve {
    final w = widget.trailingReserveWidth;
    if (w == null || w <= 0) return null;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SizedBox(width: w, height: 1),
    );
  }

  List<InlineSpan> _mentionSpans(BuildContext context, String source) {
    final mentionStyle = widget.style.copyWith(
      color: widget.mentionColor ?? Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _mentionRe.allMatches(source)) {
      if (m.start > start) {
        spans.add(TextSpan(text: source.substring(start, m.start)));
      }
      final mention = m.group(0)!;
      final handle = mention.substring(1);
      if (widget.onMentionTap != null) {
        spans.add(
          TextSpan(
            text: mention,
            style: mentionStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => widget.onMentionTap!(handle),
          ),
        );
      } else {
        spans.add(TextSpan(text: mention, style: mentionStyle));
      }
      start = m.end;
    }
    if (start < source.length) {
      spans.add(TextSpan(text: source.substring(start)));
    }
    return spans;
  }

  List<InlineSpan> _plainOrMentions(BuildContext context, String source) {
    if (!widget.highlightMentions) {
      return [TextSpan(text: source)];
    }
    return _mentionSpans(context, source);
  }

  List<InlineSpan> _markupSpans(BuildContext context, String source) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var start = 0;
    var spoilerIndex = 0;
    for (final m in _markupRe.allMatches(source)) {
      if (m.start > start) {
        spans.addAll(
          _plainOrMentions(context, source.substring(start, m.start)),
        );
      }
      if (m.group(1) != null) {
        final inner = m.group(1)!;
        final idx = spoilerIndex++;
        final revealed = _revealedSpoilers.contains(idx);
        spans.add(
          TextSpan(
            text: revealed ? inner : '█' * (inner.length.clamp(2, 24)),
            style: widget.style.copyWith(
              color: revealed
                  ? widget.style.color
                  : scheme.onSurface.withValues(alpha: 0.55),
              backgroundColor: revealed
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
                  : scheme.onSurface.withValues(alpha: 0.22),
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  if (_revealedSpoilers.contains(idx)) {
                    _revealedSpoilers.remove(idx);
                  } else {
                    _revealedSpoilers.add(idx);
                  }
                });
              },
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: widget.style.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: widget.style.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (m.group(4) != null) {
        spans.add(
          TextSpan(
            text: m.group(4),
            style: widget.style.copyWith(
              fontFamily: 'monospace',
              backgroundColor:
                  scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
          ),
        );
      }
      start = m.end;
    }
    if (start < source.length) {
      spans.addAll(_plainOrMentions(context, source.substring(start)));
    }
    return spans;
  }

  List<InlineSpan> _querySpans(BuildContext context) {
    final q = widget.query!.trim().toLowerCase();
    final text = widget.text;
    final lower = text.toLowerCase();
    final spans = <InlineSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) {
        if (start < text.length) {
          final rest = text.substring(start);
          spans.addAll(
            widget.parseMarkup
                ? _markupSpans(context, rest)
                : _plainOrMentions(context, rest),
          );
        }
        break;
      }
      if (index > start) {
        final chunk = text.substring(start, index);
        spans.addAll(
          widget.parseMarkup
              ? _markupSpans(context, chunk)
              : _plainOrMentions(context, chunk),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: widget.style.copyWith(
            backgroundColor: widget.highlightColor ??
                Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + q.length;
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final reserve = _trailingReserve;
    final q = widget.query?.trim().toLowerCase();
    final hasQuery = q != null && q.isNotEmpty;
    final needsRich = hasQuery ||
        widget.highlightMentions ||
        widget.parseMarkup ||
        reserve != null;

    if (!needsRich) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final spans = <InlineSpan>[];
    if (hasQuery) {
      spans.addAll(_querySpans(context));
    } else if (widget.parseMarkup) {
      spans.addAll(_markupSpans(context, widget.text));
    } else if (widget.highlightMentions) {
      spans.addAll(_mentionSpans(context, widget.text));
    } else {
      spans.add(TextSpan(text: widget.text));
    }
    if (reserve != null) spans.add(reserve);

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
