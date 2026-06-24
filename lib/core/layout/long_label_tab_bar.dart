import 'package:flutter/material.dart';

import '../../widgets/app_modern_tabs.dart';

/// TabBar с прокруткой по горизонтали: длинные русские подписи не обрезаются.
TabBar longLabelTabBar({
  required BuildContext context,
  TabController? controller,
  required List<Widget> tabs,
  TabAlignment tabAlignment = TabAlignment.center,
  EdgeInsetsGeometry labelPadding =
      const EdgeInsets.symmetric(horizontal: 12),
}) {
  return appModernTabBar(
    context: context,
    controller: controller,
    isScrollable: true,
    tabAlignment: tabAlignment,
    labelPadding: labelPadding,
    tabs: tabs,
  );
}
