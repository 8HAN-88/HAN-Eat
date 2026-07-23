import 'package:flutter/material.dart';

import '../../../../models/chat_poll.dart';

/// Пузырь опроса в чате (стиль Telegram).
class ChatPollBubble extends StatelessWidget {
  const ChatPollBubble({
    super.key,
    required this.poll,
    required this.foregroundColor,
    required this.accentColor,
    required this.mutedColor,
    required this.optionBackground,
    this.onVote,
    this.voting = false,
    this.canClose = false,
    this.onClose,
    this.closing = false,
    this.onShowVoters,
  });

  final ChatPollMessage poll;
  final Color foregroundColor;
  final Color accentColor;
  final Color mutedColor;
  final Color optionBackground;
  final ValueChanged<int>? onVote;
  final bool voting;
  final bool canClose;
  final VoidCallback? onClose;
  final bool closing;
  final VoidCallback? onShowVoters;

  bool get _quiz => poll.settings.quizMode;

  bool _isCorrect(int index) =>
      poll.settings.correctOptionIndices.contains(index);

  @override
  Widget build(BuildContext context) {
    final options = poll.options;
    final showResults = poll.showResults;
    final canOpenVoters = showResults &&
        poll.settings.showVoterNames &&
        poll.totalVotes > 0 &&
        onShowVoters != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _quiz ? Icons.quiz_outlined : Icons.poll_outlined,
              size: 18,
              color: accentColor,
            ),
            const SizedBox(width: 6),
            Text(
              _quiz ? 'Викторина' : 'Опрос',
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (poll.isClosed) ...[
              const SizedBox(width: 8),
              Text(
                'завершён',
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          poll.question,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        if (poll.description.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            poll.description,
            style: TextStyle(color: mutedColor, fontSize: 13),
          ),
        ],
        if (poll.settings.multipleChoice)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Можно выбрать несколько вариантов',
              style: TextStyle(color: mutedColor, fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        ...options.map((option) {
          final selected = poll.votedOptionIndices.contains(option.index);
          final fraction = (option.percentage / 100).clamp(0.0, 1.0);
          final correct = _quiz && showResults && _isCorrect(option.index);
          final wrongPick =
              _quiz && showResults && selected && !_isCorrect(option.index);
          final barColor = correct
              ? const Color(0xFF3D9B5F)
              : wrongPick
                  ? const Color(0xFFD3544D)
                  : selected
                      ? accentColor
                      : accentColor.withValues(alpha: 0.55);

          if (!showResults) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: optionBackground,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: (voting || poll.isClosed || onVote == null)
                      ? null
                      : () => onVote!(option.index),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Text(
                      option.text,
                      style: TextStyle(color: foregroundColor, fontSize: 14),
                    ),
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: (voting ||
                      poll.isClosed ||
                      onVote == null ||
                      !poll.settings.allowChangeVote)
                  ? null
                  : () => onVote!(option.index),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (correct || selected || wrongPick)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            correct
                                ? Icons.check_circle
                                : wrongPick
                                    ? Icons.cancel
                                    : Icons.check_circle,
                            size: 16,
                            color: correct
                                ? const Color(0xFF3D9B5F)
                                : wrongPick
                                    ? const Color(0xFFD3544D)
                                    : accentColor,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          option.text,
                          style: TextStyle(
                            color: foregroundColor,
                            fontWeight: (selected || correct)
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        '${option.percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 5,
                      backgroundColor: optionBackground,
                      color: barColor,
                    ),
                  ),
                  if (option.votes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${option.votes} ${_votesLabel(option.votes)}',
                        style: TextStyle(color: mutedColor, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        if (poll.totalVotes > 0)
          Text(
            '${poll.totalVotes} ${_votesLabel(poll.totalVotes)}',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
        if (canOpenVoters) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onShowVoters,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Кто голосовал',
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
        if (canClose && !poll.isClosed && onClose != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onLongPress: () {},
            behavior: HitTestBehavior.opaque,
            child: TextButton(
              onPressed: (closing || voting) ? null : onClose,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: closing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    )
                  : Text(
                      'Закрыть опрос',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
        if (voting)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

String _votesLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'голосов';
  if (mod10 == 1) return 'голос';
  if (mod10 >= 2 && mod10 <= 4) return 'голоса';
  return 'голосов';
}
