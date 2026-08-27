import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/highlighted_text.dart';

Future<void> showFlexGiftSheet(
  BuildContext context, {
  required FlexMe me,
  required String plan,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _FlexGiftSheet(me: me, plan: plan),
  );
}

class _FlexGiftSheet extends StatefulWidget {
  const _FlexGiftSheet({required this.me, required this.plan});

  final FlexMe me;
  final String plan;

  @override
  State<_FlexGiftSheet> createState() => _FlexGiftSheetState();
}

class _FlexGiftSheetState extends State<_FlexGiftSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _paying = false;
  List<ChatUserSearchItem> _results = const [];
  ChatUserSearchItem? _picked;
  late int _level;
  late String _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _level = widget.me.currentLevel < 1 ? 6 : widget.me.currentLevel;
    _plan = widget.plan;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = items;
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

  Future<void> _pay() async {
    final picked = _picked;
    if (picked == null || _paying) return;
    final price = widget.me.priceForPlan(_level, _plan);
    final period = widget.me.periodLabel(_plan);
    final name = picked.name ?? picked.username ?? '#${picked.id}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подарить подписку?'),
        content: Text(
          'Уровень $_level · $price ₽ / $period\nПолучатель: ${previewTextWithCustomEmoji(name)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Подарить за $price ₽'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying = true);
    try {
      await FlexSubscriptionApi.giftCheckout(
        recipientUserId: picked.id,
        level: _level,
        plan: _plan,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.me.priceForPlan(_level, _plan);
    final period = widget.me.periodLabel(_plan);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Подарить подписку',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text('Уровень $_level · $price ₽ / $period'),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'monthly', label: Text('Месяц')),
                    ButtonSegment(value: 'yearly', label: Text('Год −2 мес.')),
                  ],
                  selected: {_plan},
                  onSelectionChanged: (next) => setState(() => _plan = next.first),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var level = 1; level <= widget.me.maxLevel; level++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$level'),
                            selected: _level == level,
                            onSelected: (_) => setState(() => _level = level),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Кому: имя или @username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onQueryChanged,
                ),
                if (_picked != null) ...[
                  const SizedBox(height: 8),
                  HighlightedText(
                    text:
                        'Получатель: ${_picked!.name ?? _picked!.username ?? '#${_picked!.id}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final user = _results[index];
                            return ListTile(
                              title: HighlightedText(
                                text: user.name ?? user.username ?? '#${user.id}',
                                style: Theme.of(context).textTheme.bodyLarge ??
                                    const TextStyle(fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: user.username != null ? Text('@${user.username}') : null,
                              selected: _picked?.id == user.id,
                              onTap: () => setState(() => _picked = user),
                            );
                          },
                        ),
                ),
                FilledButton(
                  onPressed: _picked == null || _paying ? null : _pay,
                  child: Text(_paying ? 'Открываем оплату…' : 'Подарить за $price ₽'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
