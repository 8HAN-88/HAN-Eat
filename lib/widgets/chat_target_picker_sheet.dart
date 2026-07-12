import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import 'app_avatar.dart';

Future<ChatConversation?> showChatTargetPicker(
  BuildContext context, {
  required List<ChatConversation> chats,
  required String title,
  int? excludeConversationId,
}) {
  final candidates = chats
      .where(
          (c) => excludeConversationId == null || c.id != excludeConversationId)
      .toList(growable: false)
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  return showModalBottomSheet<ChatConversation>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ChatTargetPickerSheet(
      title: title,
      items: candidates,
    ),
  );
}

class _ChatTargetPickerSheet extends StatefulWidget {
  const _ChatTargetPickerSheet({
    required this.title,
    required this.items,
  });

  final String title;
  final List<ChatConversation> items;

  @override
  State<_ChatTargetPickerSheet> createState() => _ChatTargetPickerSheetState();
}

class _ChatTargetPickerSheetState extends State<_ChatTargetPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'Чаты не найдены',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final chat = filtered[i];
                        final isSaved = chat.isSaved;
                        final isGroup = chat.isGroup;
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
                          trailing: chat.pinned
                              ? Icon(Icons.push_pin_rounded,
                                  color: scheme.primary, size: 18)
                              : null,
                          onTap: () => Navigator.pop(context, chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
