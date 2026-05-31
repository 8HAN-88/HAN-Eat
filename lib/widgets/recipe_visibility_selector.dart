import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../features/subscription/subscription_copy.dart';

/// public | private | mixed — режим канала по умолчанию для рецептов.
typedef ChannelRecipeVisibilityMode = String;

class RecipeVisibilitySelector extends StatelessWidget {
  const RecipeVisibilitySelector({
    super.key,
    required this.value,
    required this.hasCreator,
    required this.onChanged,
    this.channelMode,
  });

  final String value;
  final bool hasCreator;
  final ValueChanged<String> onChanged;
  final ChannelRecipeVisibilityMode? channelMode;

  static String defaultForChannel(String? mode, {required bool hasCreator}) {
    switch (mode) {
      case 'private':
        return hasCreator ? 'private' : 'public';
      case 'public':
        return 'public';
      default:
        return 'public';
    }
  }

  bool get _modeLocksPublic => channelMode == 'public';
  bool get _modeLocksPrivate => channelMode == 'private' && hasCreator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveValue = _modeLocksPrivate
        ? 'private'
        : _modeLocksPublic
            ? 'public'
            : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          SubscriptionCopy.recipeVisibilitySectionTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _VisibilityTile(
          optionValue: 'public',
          groupValue: effectiveValue,
          icon: Icons.public_outlined,
          title: SubscriptionCopy.recipeVisibilityPublicTitle,
          subtitle: SubscriptionCopy.recipeVisibilityPublicSubtitle,
          enabled: !_modeLocksPrivate,
          onSelect: () => onChanged('public'),
        ),
        const SizedBox(height: 8),
        _VisibilityTile(
          optionValue: 'private',
          groupValue: effectiveValue,
          icon: Icons.lock_outline,
          title: SubscriptionCopy.recipeVisibilityPrivateTitle,
          subtitle: hasCreator
              ? SubscriptionCopy.recipeVisibilityPrivateSubtitle
              : SubscriptionCopy.recipeVisibilityPrivateLockedSubtitle,
          enabled: hasCreator && !_modeLocksPublic,
          onSelect: hasCreator && !_modeLocksPublic
              ? () => onChanged('private')
              : () => context.push(SubscriptionRoute.pathWithProduct('creator')),
          trailing: !hasCreator
              ? TextButton(
                  onPressed: () => context.push(
                    SubscriptionRoute.pathWithProduct('creator'),
                  ),
                  child: Text(SubscriptionCopy.recipeVisibilityPrivateCta),
                )
              : null,
        ),
        if (_modeLocksPublic) ...[
          const SizedBox(height: 8),
          Text(
            SubscriptionCopy.recipeVisibilityChannelPublicHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_modeLocksPrivate) ...[
          const SizedBox(height: 8),
          Text(
            SubscriptionCopy.recipeVisibilityChannelPrivateHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _VisibilityTile extends StatelessWidget {
  const _VisibilityTile({
    required this.optionValue,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onSelect,
    this.trailing,
  });

  final String optionValue;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onSelect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = groupValue == optionValue;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Radio<String>(
                  value: optionValue,
                  groupValue: groupValue,
                  onChanged: (_) => onSelect(),
                ),
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: смена видимости существующего рецепта в канале.
Future<String?> showChangeRecipeVisibilitySheet(
  BuildContext context, {
  required String currentVisibility,
  required bool hasCreator,
  String? channelMode,
}) async {
  var selected = currentVisibility == 'private' ? 'private' : 'public';

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  SubscriptionCopy.recipeVisibilityChangeTitle,
                  style: Theme.of(ctx).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                RecipeVisibilitySelector(
                  value: selected,
                  hasCreator: hasCreator,
                  channelMode: channelMode,
                  onChanged: (v) => setSheetState(() => selected = v),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(selected),
                  child: const Text('Сохранить'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
