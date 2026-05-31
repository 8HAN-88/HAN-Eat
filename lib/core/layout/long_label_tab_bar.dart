import 'package:flutter/material.dart';

/// TabBar с прокруткой по горизонтали: длинные русские подписи не обрезаются.
///
/// Ширина вкладок по тексту; на узком экране полосу вкладок можно слегка прокрутить.
TabBar longLabelTabBar({
  TabController? controller,
  required List<Widget> tabs,
  TabAlignment tabAlignment = TabAlignment.center,
  EdgeInsetsGeometry labelPadding =
      const EdgeInsets.symmetric(horizontal: 12),
}) {
  return TabBar(
    controller: controller,
    isScrollable: true,
    tabAlignment: tabAlignment,
    indicatorSize: TabBarIndicatorSize.label,
    labelPadding: labelPadding,
    tabs: tabs,
  );
}
