import 'package:flutter/material.dart';

import '../../../../models/chat_models.dart';

class ChatChecklistBubble extends StatelessWidget {
  const ChatChecklistBubble({
    super.key,
    required this.checklist,
    required this.foregroundColor,
    required this.accentColor,
    required this.mutedColor,
    this.onToggle,
    this.busy = false,
  });

  final ChatChecklist checklist;
  final Color foregroundColor;
  final Color accentColor;
  final Color mutedColor;
  final void Function(int index, bool done)? onToggle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 196, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, size: 18, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  checklist.title,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${checklist.doneCount}/${checklist.items.length}',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < checklist.items.length; i++)
            InkWell(
              onTap: busy || onToggle == null
                  ? null
                  : () => onToggle!(i, !checklist.items[i].done),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      checklist.items[i].done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 22,
                      color: checklist.items[i].done ? accentColor : mutedColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        checklist.items[i].text,
                        style: TextStyle(
                          color: foregroundColor,
                          decoration: checklist.items[i].done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: mutedColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
