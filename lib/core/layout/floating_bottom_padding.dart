import 'package:flutter/material.dart';

import '../../features/navigation/application/feed_scroll_chrome.dart';

/// Дополнительный отступ снизу под плавающую нижнюю панель в [RootShell]
/// (совместимо с `extendBody: true`).
double floatingBottomPadding(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  const gap = 8.0;
  return safeBottom +
      kShellNavBottomMarginExpanded +
      kShellNavExpandedHeight +
      gap;
}

/// Дополнительный отступ для FAB над плавающей [NavigationBar] в [RootShell].
///
/// [Scaffold] уже поднимает FAB на `kFloatingActionButtonMargin` + нижний safe inset,
/// поэтому сюда не добавляем повторно `MediaQuery.padding.bottom` — только «коробку»
/// панели (отступ shell + высота bar) и зазор, минус стандартный отступ FAB.
double fabExtraBottomPadding(BuildContext _) {
  const gapAboveNavBar = 42.0;
  const scaffoldFabMargin = 16.0; // kFloatingActionButtonMargin
  return kShellNavBottomMarginExpanded +
      kShellNavExpandedHeight +
      gapAboveNavBar -
      scaffoldFabMargin;
}

/// [FloatingActionButton] / speed dial над плавающей нижней панелью [RootShell]
/// (`extendBody: true`), чтобы не перекрывалась с NavigationBar.
Widget floatingActionButtonClearOfBottomNav(
  BuildContext context, {
  required Widget child,
}) {
  return Padding(
    padding: EdgeInsets.only(bottom: fabExtraBottomPadding(context)),
    child: child,
  );
}
