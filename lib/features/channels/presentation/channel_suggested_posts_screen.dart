import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../../widgets/highlighted_text.dart';

/// Telegram-like paid suggested posts for a channel.
class ChannelSuggestedPostsScreen extends StatefulWidget {
  const ChannelSuggestedPostsScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.canManage = false,
    this.isOwner = false,
  });

  final int channelId;
  final String channelName;
  final bool canManage;
  final bool isOwner;

  @override
  State<ChannelSuggestedPostsScreen> createState() =>
      _ChannelSuggestedPostsScreenState();
}

class _ChannelSuggestedPostsScreenState
    extends State<ChannelSuggestedPostsScreen> {
  bool _loading = true;
  String? _error;
  List<ChannelSuggestedPost> _items = const [];
  final Set<int> _busy = {};

  bool get _canSuggest => !widget.isOwner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PaidFeaturesService.listSuggestedPosts(
        widget.channelId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  Future<void> _suggest() async {
    final textController = TextEditingController();
    final starsController = TextEditingController(text: '50');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            final text = textController.text.trim();
            final stars = int.tryParse(starsController.text.trim()) ?? 0;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Предложить пост',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Как в Telegram: звёзды спишутся сразу. Если админ отклонит — вернутся.',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Текст поста',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: starsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Оплата ★',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: text.isNotEmpty && stars >= 10
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          child: const Text('Отправить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final text = textController.text.trim();
    final stars = int.tryParse(starsController.text.trim()) ?? 0;
    textController.dispose();
    starsController.dispose();
    if (ok != true || !mounted) return;
    final confirmed = await confirmStarsSpend(
      context,
      title: 'Предложить пост',
      body: 'С баланса спишется $stars ★. При отклонении они вернутся.',
      amountStars: stars,
      confirmLabel: 'Предложить',
    );
    if (!confirmed || !mounted) return;
    try {
      await PaidFeaturesService.suggestChannelPost(
        widget.channelId,
        text: text,
        amountStars: stars,
      );
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Предложение отправлено')),
      );
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _review(ChannelSuggestedPost post, {required bool approve}) async {
    if (_busy.contains(post.id)) return;
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отклонить предложение?'),
          content: const Text('Звёзды вернутся автору, пост не опубликуется.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Назад'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отклонить'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy.add(post.id));
    try {
      final next = await PaidFeaturesService.reviewSuggestedPost(
        post.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == next.id ? next : e).toList();
        _busy.remove(post.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Пост опубликован' : 'Предложение отклонено'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(post.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'На рассмотрении';
      case 'accepted':
        return 'Опубликован';
      case 'rejected':
        return 'Отклонён';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: HighlightedText(
          text: widget.channelName,
          leading: 'Предложения · ',
          style: Theme.of(context).textTheme.titleLarge ??
              const TextStyle(fontSize: 20),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_canSuggest)
            IconButton(
              tooltip: 'Предложить',
              onPressed: _suggest,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      floatingActionButton: _canSuggest
          ? FloatingActionButton.extended(
              onPressed: _suggest,
              icon: const Icon(Icons.outgoing_mail),
              label: const Text('Предложить'),
            )
          : null,
      body: AppGradientBackground(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Повторить')),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          64,
          24,
          24 + floatingBottomPadding(context),
        ),
        children: [
          const Icon(Icons.outgoing_mail, size: 48),
          const SizedBox(height: 12),
          Text(
            widget.canManage
                ? 'Пока нет предложенных постов.'
                : 'Предложите пост в канал за ★ — админ примет или вернёт оплату.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        16 + floatingBottomPadding(context),
      ),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final post = _items[index];
        final busy = _busy.contains(post.id);
        final scheme = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightedText(
                  text: post.authorLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                HighlightedText(
                  text: post.text,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  '${post.amountStars} ★ · ${_statusLabel(post.status)}',
                  style: TextStyle(
                    color: post.status == 'accepted'
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.canManage && post.status == 'pending') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(_review(post, approve: true)),
                        child: const Text('Опубликовать'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(_review(post, approve: false)),
                        child: const Text('Отклонить'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
