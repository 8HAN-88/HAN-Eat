import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Секция опроса — карточка с заголовком и контентом.
class SurveySectionCard extends StatelessWidget {
  const SurveySectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 18 : 22, 20, compact ? 18 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.14),
                          AppColors.secondary.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 22, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 16 : 20),
            child,
          ],
        ),
      ),
    );
  }
}

/// Вертикальный список вариантов с иконкой и необязательным подзаголовком.
class SurveyOptionList extends StatelessWidget {
  const SurveyOptionList({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<SurveyOption> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SurveyOptionTile(
            option: options[i],
            selected: selected == options[i].id,
            onTap: () => onSelected(options[i].id),
          ),
        ],
      ],
    );
  }
}

class SurveyOption {
  const SurveyOption({
    required this.id,
    required this.label,
    required this.icon,
    this.subtitle,
  });

  final String id;
  final String label;
  final IconData icon;
  final String? subtitle;
}

class _SurveyOptionTile extends StatelessWidget {
  const _SurveyOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SurveyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? primary.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? primary.withValues(alpha: 0.55)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? primary.withValues(alpha: 0.16)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    option.icon,
                    size: 22,
                    color: selected ? primary : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (option.subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          option.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), color: primary)
                      : Icon(
                          Icons.circle_outlined,
                          key: const ValueKey('off'),
                          color: theme.colorScheme.outlineVariant,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
