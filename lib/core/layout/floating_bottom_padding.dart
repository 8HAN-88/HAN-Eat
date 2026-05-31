import 'package:flutter/material.dart';

/// Дополнительный отступ снизу под плавающую нижнюю панель в [RootShell]
/// (совместимо с `extendBody: true`).
double floatingBottomPadding(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  const barHeight = 68.0;
  const shellMargin = 10.0;
  const gap = 8.0;
  return safeBottom + barHeight + shellMargin + gap;
}

/// Дополнительный отступ для FAB над плавающей [NavigationBar] в [RootShell].
///
/// [Scaffold] уже поднимает FAB на `kFloatingActionButtonMargin` + нижний safe inset,
/// поэтому сюда не добавляем повторно `MediaQuery.padding.bottom` — только «коробку»
/// панели (отступ shell + высота bar) и зазор, минус стандартный отступ FAB.
double fabExtraBottomPadding(BuildContext _) {
  const shellMargin = 10.0;
  const barHeight = 68.0;
  // Зазор между нижним краем FAB и верхом плавающей панели (RootShell + скругление плашки).
  const gapAboveNavBar = 42.0;
  const scaffoldFabMargin = 16.0; // kFloatingActionButtonMargin
  return shellMargin + barHeight + gapAboveNavBar - scaffoldFabMargin;
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
