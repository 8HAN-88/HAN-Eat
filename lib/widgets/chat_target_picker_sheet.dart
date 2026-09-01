import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import 'app_avatar.dart';

class ChatTargetPickResult {
  const ChatTargetPickResult({
    required this.chat,
    this.chats = const [],
    this.asCopy = false,
  });

  /// Primary / first selected chat (kept for single-select callers).
  final ChatConversation chat;
  final List<ChatConversation> chats;
  final bool asCopy;

  List<ChatConversation> get targets {
    if (chats.isNotEmpty) return chats;
    return [chat];
  }
}

Future<ChatConversation?> showChatTargetPicker(
  BuildContext context, {
  required List<ChatConversation> chats,
  required String title,
  int? excludeConversationId,
  bool enableAsCopy = false,
}) async {
  final result = await showChatTargetPickerResult(
    context,
    chats: chats,
    title: title,
    excludeConversationId: excludeConversationId,
    enableAsCopy: enableAsCopy,
  );
  return result?.chat;
}

Future<ChatTargetPickResult?> showChatTargetPickerResult(
  BuildContext context, {
  required List<ChatConversation> chats,
  required String title,
  int? excludeConversationId,
  bool enableAsCopy = false,
  bool allowMultiSelect = false,
}) {
  final candidates = chats
      .where(
          (c) => excludeConversationId == null || c.id != excludeConversationId)
      .toList(growable: false)
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  return showModalBottomSheet<ChatTargetPickResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ChatTargetPickerSheet(
      title: title,
      items: candidates,
      enableAsCopy: enableAsCopy,
      allowMultiSelect: allowMultiSelect,
    ),
  );
}

class _ChatTargetPickerSheet extends StatefulWidget {
  const _ChatTargetPickerSheet({
    required this.title,
    required this.items,
    this.enableAsCopy = false,
    this.allowMultiSelect = false,
  });

  final String title;
  final List<ChatConversation> items;
  final bool enableAsCopy;
  final bool allowMultiSelect;

  @override
  State<_ChatTargetPickerSheet> createState() => _ChatTargetPickerSheetState();
}

class _ChatTargetPickerSheetState extends State<_ChatTargetPickerSheet> {
  final _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  bool _asCopy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(ChatConversation chat) {
    setState(() {
      if (_selectedIds.contains(chat.id)) {
        _selectedIds.remove(chat.id);
      } else {
        _selectedIds.add(chat.id);
      }
    });
  }

  void _confirmMulti() {
    final selected = widget.items
        .where((c) => _selectedIds.contains(c.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    Navigator.pop(
      context,
      ChatTargetPickResult(
        chat: selected.first,
        chats: selected,
        asCopy: _asCopy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = widget.items.where((c) {
      if (q.isEmpty) return true;
      final title = c.displayTitle.toLowerCase();
      final username = c.peer?.username?.toLowerCase() ?? '';
      return title.contains(q) || username.contains(q);
    }).toList(growable: false);
    final multi = widget.allowMultiSelect;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              widget.title,
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (multi) ...[
              const SizedBox(height: 4),
              Text(
                'Можно выбрать несколько чатов',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Поиск чата',
                isDense: true,
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (widget.enableAsCopy) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.content_copy_outlined),
                title: const Text('Переслать как копию'),
                subtitle: const Text('Без подписи «Переслано от…»'),
                value: _asCopy,
                onChanged: (v) => setState(() => _asCopy = v),
              ),
            ],
            const SizedBox(height: 6),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Text(
                            q.isEmpty
                                ? 'Нет чатов для пересылки'
                                : 'Чаты не найдены',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: q.isNotEmpty
                                ? () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  }
                                : () => Navigator.of(context).maybePop(),
                            child: Text(
                              q.isNotEmpty ? 'Очистить поиск' : 'Закрыть',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final chat = filtered[i];
                        final isSaved = chat.isSaved;
                        final isGroup = chat.isGroup;
                        final selected = _selectedIds.contains(chat.id);
                        final subtitle = isSaved
                            ? 'Личные сохраненные сообщения'
                            : isGroup
                                ? 'Группа'
                                : (chat.peer?.username != null
                                    ? '@${chat.peer!.username}'
                                    : 'Личный чат');
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: isSaved
                              ? CircleAvatar(
                                  radius: 20,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Icon(
                                    Icons.bookmark_rounded,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                )
                              : AppUserAvatar(
                                  radius: 20,
                                  imageUrl: chat.peer?.avatarUrl,
                                  displayName: chat.displayTitle,
                                ),
                          title: Text(
                            chat.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: multi
                              ? Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggle(chat),
                                )
                              : (chat.pinned
                                  ? Icon(Icons.push_pin_rounded,
                                      color: scheme.primary, size: 18)
                                  : null),
                          selected: multi && selected,
                          onTap: () {
                            if (multi) {
                              _toggle(chat);
                              return;
                            }
                            Navigator.pop(
                              context,
                              ChatTargetPickResult(
                                chat: chat,
                                asCopy: _asCopy,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            if (multi) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : _confirmMulti,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Выберите чаты'
                        : 'Переслать (${_selectedIds.length})',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
