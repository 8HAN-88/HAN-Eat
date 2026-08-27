import 'package:flutter/material.dart';

import '../../../widgets/highlighted_text.dart';
import '../data/bot_inline_service.dart';

/// Overlay с результатами inline-режима (@bot query)
/// Используется как для отправки сообщения, так и для live-подсказок при вводе.
class InlineSuggestions extends StatelessWidget {
  const InlineSuggestions({
    super.key,
    required this.results,
    required this.onSelect,
    this.botUsername,
    this.maxHeight = 240,
  });

  final List<InlineResult> results;
  final void Function(InlineResult) onSelect;
  final String? botUsername;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: results.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) {
            final r = results[index];
            final icon = r.type == 'miniapp' ? Icons.apps_rounded : Icons.code;
            return ListTile(
              dense: true,
              leading: Icon(icon, size: 20),
              title: HighlightedText(
                text: r.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: HighlightedText(
                text: r.description,
                style: Theme.of(context).textTheme.bodySmall ??
                    const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onSelect(r),
            );
          },
        ),
      ),
    );
  }
}
