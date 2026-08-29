import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// На web горизонтальный Cupertino-слайд рисует два экрана рядом
/// и на iPhone PWA часто залипает полоской предыдущего маршрута.
class WebFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const WebFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

PageTransitionsTheme appPageTransitionsTheme() {
  if (kIsWeb) {
    return PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const WebFadePageTransitionsBuilder(),
      },
    );
  }
  return const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );
}
