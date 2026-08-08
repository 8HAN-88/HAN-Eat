import 'package:flutter/material.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/chat_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_avatar.dart';

Future<void> showChatMessageReactorsSheet(
  BuildContext context, {
  required int conversationId,
  required int messageId,
  String? initialEmoji,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ChatMessageReactorsSheet(
      conversationId: conversationId,
      messageId: messageId,
      initialEmoji: initialEmoji,
    ),
  );
}

class _ChatMessageReactorsSheet extends StatefulWidget {
  const _ChatMessageReactorsSheet({
    required this.conversationId,
    required this.messageId,
    this.initialEmoji,
  });

  final int conversationId;
  final int messageId;
  final String? initialEmoji;

  @override
  State<_ChatMessageReactorsSheet> createState() =>
      _ChatMessageReactorsSheetState();
}

class _ChatMessageReactorsSheetState extends State<_ChatMessageReactorsSheet> {
  bool _loading = true;
  Object? _error;
  List<ChatMessageReactionUser> _items = const [];
  String? _filterEmoji;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmoji?.trim();
    _filterEmoji =
        (initial != null && initial.isNotEmpty) ? initial : null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ChatService.listMessageReactions(
        conversationId: widget.conversationId,
        messageId: widget.messageId,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<String> get _emojiTabs {
    final seen = <String>{};
    final out = <String>[];
    for (final item in _items) {
      final emoji = item.emoji.trim();
      if (emoji.isEmpty || seen.contains(emoji)) continue;
      seen.add(emoji);
      out.add(emoji);
    }
    return out;
  }

  List<ChatMessageReactionUser> get _visible {
    final filter = _filterEmoji;
    final base = (filter == null || filter.isEmpty)
        ? _items
        : _items.where((e) => e.emoji == filter).toList();
    // Paid reactions: keep top ★ senders first (API already sorts; keep UI stable).
    final sorted = [...base]..sort((a, b) {
        final byStars = b.starsAmount.compareTo(a.starsAmount);
        if (byStars != 0) return byStars;
        return a.user.displayName.compareTo(b.user.displayName);
      });
    return sorted;
  }

  int get _starsTotal =>
      _items.fold<int>(0, (sum, e) => sum + (e.starsAmount > 0 ? e.starsAmount : 0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tabs = _emojiTabs;
    final visible = _visible;
    final starsTotal = _starsTotal;
    final subtitle = _loading
        ? 'Загрузка…'
        : (_items.isEmpty
            ? 'Пока нет реакций'
            : (starsTotal > 0
                ? 'Реакций: ${_items.length} · $starsTotal ★'
                : 'Реакций: ${_items.length}'));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.46,
        minChildSize: 0.3,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Кто поставил реакцию',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (!_loading && _error == null && tabs.isNotEmpty) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: const Text('Все'),
                          selected: _filterEmoji == null,
                          onSelected: (_) =>
                              setState(() => _filterEmoji = null),
                        ),
                      ),
                      for (final emoji in tabs)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(
                              '$emoji ${_items.where((e) => e.emoji == emoji).length}',
                            ),
                            selected: _filterEmoji == emoji,
                            onSelected: (_) =>
                                setState(() => _filterEmoji = emoji),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    userVisibleError(_error!),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : visible.isEmpty
                            ? ListView(
                                controller: scrollController,
                                children: const [
                                  SizedBox(height: 48),
                                  Icon(Icons.emoji_emotions_outlined, size: 40),
                                  SizedBox(height: 12),
                                  Text(
                                    'Реакций пока нет',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: visible.length,
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  final user = item.user;
                                  return ListTile(
                                    leading: AppUserAvatar(
                                      imageUrl: user.avatarUrl,
                                      displayName: user.displayName,
                                      radius: 22,
                                    ),
                                    title: Text(user.displayName),
                                    subtitle: user.username != null &&
                                            user.username!.trim().isNotEmpty
                                        ? Text(
                                            user.username!.startsWith('@')
                                                ? user.username!
                                                : '@${user.username}',
                                          )
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (item.starsAmount > 0) ...[
                                          Text(
                                            '${item.starsAmount} ★',
                                            style: TextStyle(
                                              color: scheme.secondary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          item.emoji,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}
