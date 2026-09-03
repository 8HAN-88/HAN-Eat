import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../services/api_service.dart';
import '../services/post_reaction_service.dart';
import '../services/subscription_status_cache.dart';
import '../features/subscription/application/flex_entitlements.dart';
import '../utils/session_snackbar.dart';

/// Реакции к посту. Ставятся из комментариев, не с карточки ленты.
class PostReactionsBar extends StatefulWidget {
  const PostReactionsBar({
    super.key,
    required this.postId,
    this.initialReactions = const [],
  });

  final int postId;
  final List<PostReactionChip> initialReactions;

  @override
  State<PostReactionsBar> createState() => _PostReactionsBarState();
}

class _PostReactionsBarState extends State<PostReactionsBar> {
  late List<PostReactionChip> _reactions;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reactions = widget.initialReactions;
    if (_reactions.isEmpty) {
      unawaited(_hydrateFromPost());
    }
  }

  @override
  void didUpdateWidget(covariant PostReactionsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _reactions = widget.initialReactions;
      if (_reactions.isEmpty) unawaited(_hydrateFromPost());
    }
  }

  Future<void> _hydrateFromPost() async {
    try {
      final post = await ApiService.getPostById(widget.postId);
      if (!mounted || post == null || post.reactions.isEmpty) return;
      setState(() => _reactions = post.reactions);
    } catch (_) {}
  }

  Future<void> _toggle(String emoji) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await PostReactionService.toggle(
        postId: widget.postId,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() => _reactions = next);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallback: 'Не удалось поставить реакцию',
        onRetry: () => unawaited(_toggle(emoji)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exclusive = SubscriptionStatusCache.peek()
            ?.hasEntitlement('exclusive_reactions') ??
        false;
    final choices = flexPostReactions(exclusive);
    final mine = {
      for (final item in _reactions)
        if (item.reactedByMe) item.emoji,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final emoji in choices)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  () {
                    final count = _reactions
                        .where((item) => item.emoji == emoji)
                        .fold<int>(0, (sum, item) => sum + item.count);
                    return count > 0 ? '$emoji $count' : emoji;
                  }(),
                ),
                backgroundColor: mine.contains(emoji)
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                onPressed: _busy ? null : () => unawaited(_toggle(emoji)),
              ),
            ),
        ],
      ),
    );
  }
}
