import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../utils/api_error_parser.dart';

/// Опрос в посте ленты / канала с возможностью голосования.
class PostPollSection extends StatefulWidget {
  const PostPollSection({
    super.key,
    required this.postId,
    required this.poll,
    this.onPollUpdated,
    this.canClose = false,
  });

  final int postId;
  final PollData poll;
  final void Function(PollData poll)? onPollUpdated;
  final bool canClose;

  @override
  State<PostPollSection> createState() => _PostPollSectionState();
}

class _PostPollSectionState extends State<PostPollSection> {
  late PollData _poll;
  bool _voting = false;
  bool _loadingVoters = false;

  @override
  void initState() {
    super.initState();
    _poll = widget.poll;
  }

  @override
  void didUpdateWidget(covariant PostPollSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll != widget.poll) {
      _poll = widget.poll;
    }
  }

  Future<void> _vote(int optionIndex) async {
    if (_voting) return;
    if (_poll.isClosed) return;
    if (_poll.votedOptionIndex == optionIndex) return;
    setState(() => _voting = true);
    try {
      final updated = await PostService.votePoll(
        postId: widget.postId,
        optionIndex: optionIndex,
      );
      if (!mounted) return;
      setState(() => _poll = updated);
      widget.onPollUpdated?.call(updated);
    } on ApiClientException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleAuthError(e, fallback: 'Не удалось выполнить действие'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось проголосовать'))),
        );
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _closePoll() async {
    if (_voting) return;
    if (_poll.isClosed) return;
    setState(() => _voting = true);
    try {
      final updated = await PostService.closePoll(postId: widget.postId);
      if (!mounted) return;
      setState(() => _poll = updated);
      widget.onPollUpdated?.call(updated);
    } on ApiClientException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleAuthError(e, fallback: 'Не удалось выполнить действие'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось закрыть опрос'))),
        );
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _showVoters() async {
    if (_loadingVoters) return;
    setState(() => _loadingVoters = true);
    try {
      final voters = await PostService.getPollVoters(postId: widget.postId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          final theme = Theme.of(context);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(
                    'Кто проголосовал',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${voters.total} ${_votesLabel(voters.total)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...voters.options.map((option) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${option.text} (${option.voters.length})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (option.voters.isEmpty)
                            Text(
                              'Пока нет голосов',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ...option.voters.map((voter) {
                            final username = voter.username?.trim();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundImage: (voter.avatarUrl != null &&
                                        voter.avatarUrl!.isNotEmpty)
                                    ? NetworkImage(voter.avatarUrl!)
                                    : null,
                                child: (voter.avatarUrl == null ||
                                        voter.avatarUrl!.isEmpty)
                                    ? const Icon(Icons.person, size: 16)
                                    : null,
                              ),
                              title: Text(voter.name),
                              subtitle: (username != null && username.isNotEmpty)
                                  ? Text('@$username')
                                  : null,
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    } on ApiClientException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleAuthError(e, fallback: 'Не удалось выполнить действие'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить голоса'))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingVoters = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalVotes =
        _poll.options.fold<int>(0, (sum, o) => sum + o.votes);
    final canVote = !_poll.isClosed;
    final showResults = _poll.isClosed || _poll.hasVoted || totalVotes > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.poll_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Опрос',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (widget.canClose && !_poll.isClosed)
                    TextButton.icon(
                      onPressed: _voting ? null : _closePoll,
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Закрыть'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                      ),
                    ),
                  if (totalVotes > 0)
                    Text(
                      '$totalVotes ${_votesLabel(totalVotes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _poll.question,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (_poll.hasVoted && !_poll.isClosed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Нажмите другой вариант, чтобы изменить голос',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ..._poll.options.asMap().entries.map((entry) {
                final option = entry.value;
                final idx = option.index;
                final isSelected = _poll.votedOptionIndex == idx;
                final fraction =
                    (option.percentage / 100).clamp(0.0, 1.0);

                if (!showResults) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: (_voting || !canVote) ? null : () => _vote(idx),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            option.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: (_voting || !canVote) ? null : () => _vote(idx),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isSelected)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  option.text,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${option.percentage.toStringAsFixed(0)}%',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHigh,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary
                                      .withValues(alpha: 0.5),
                            ),
                          ),
                          if (option.votes > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${option.votes} ${_votesLabel(option.votes)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (totalVotes > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: (_voting || _loadingVoters) ? null : _showVoters,
                    icon: _loadingVoters
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.people_outline, size: 18),
                    label: const Text('Кто проголосовал'),
                  ),
                ),
              if (_voting)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ),
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
