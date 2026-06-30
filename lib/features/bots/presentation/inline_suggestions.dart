import 'package:flutter/material.dart';
import '../data/bot_inline_service.dart';

/// Overlay с результатами inline-режима (@bot query)
class InlineSuggestions extends StatelessWidget {
  const InlineSuggestions({
    super.key,
    required this.results,
    required this.onSelect,
    this.botUsername,
  });

  final List<InlineResult> results;
  final void Function(InlineResult) onSelect;
  final String? botUsername;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 240),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final r = results[index];
            return ListTile(
              leading: const Icon(Icons.code, size: 20),
              title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSelect(r),
            );
          },
        ),
      ),
    );
  }
}
