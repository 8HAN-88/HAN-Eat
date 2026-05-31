import 'package:flutter/material.dart';

import '../features/subscription/subscription_copy.dart';

/// Бейдж public / private для карточки рецепта в канале.
class RecipeVisibilityBadge extends StatelessWidget {
  const RecipeVisibilityBadge({
    super.key,
    required this.visibility,
    this.compact = false,
  });

  final String visibility;
  final bool compact;

  bool get _isPrivate => visibility == 'private';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = _isPrivate
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.65);
    final fg = _isPrivate
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isPrivate ? Icons.lock_outline : Icons.public,
            size: compact ? 12 : 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            _isPrivate
                ? (compact
                    ? SubscriptionCopy.recipeVisibilityPrivateShort
                    : SubscriptionCopy.recipeVisibilityPrivateTitle)
                : (compact
                    ? SubscriptionCopy.recipeVisibilityPublicShort
                    : SubscriptionCopy.recipeVisibilityPublicTitle),
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
