import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Единый стиль вкладок для ленты, чатов и профиля.
TabBar appModernTabBar({
  required BuildContext context,
  TabController? controller,
  required List<Widget> tabs,
  bool isScrollable = false,
  TabAlignment tabAlignment = TabAlignment.fill,
  EdgeInsetsGeometry? labelPadding,
}) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  return TabBar(
    controller: controller,
    isScrollable: isScrollable,
    tabAlignment: tabAlignment,
    indicatorSize: TabBarIndicatorSize.label,
    dividerColor: Colors.transparent,
    splashFactory: InkRipple.splashFactory,
    labelColor: scheme.onSurface,
    unselectedLabelColor: scheme.onSurfaceVariant.withValues(alpha: 0.78),
    labelStyle: textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    unselectedLabelStyle: textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w500,
    ),
    indicator: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      color: scheme.primary.withValues(alpha: 0.14),
    ),
    labelPadding: labelPadding ??
        (isScrollable
            ? const EdgeInsets.symmetric(horizontal: 14)
            : EdgeInsets.zero),
    tabs: tabs,
  );
}
