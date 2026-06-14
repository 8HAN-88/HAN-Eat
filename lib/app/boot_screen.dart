import 'package:flutter/material.dart';

import '../widgets/app_brand_logo.dart';

/// Краткий экран между bootstrap и основным UI (только если роутер ещё на /boot).
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  static const path = '/boot';

  static const _canvas = Color(0xFF0F1319);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppBrandLogo(
                  layout: AppBrandLogoLayout.horizontal,
                  width: 168,
                ),
                SizedBox(height: 32),
                CircularProgressIndicator(
                  color: Color(0xFFFF6B35),
                  strokeWidth: 2.5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
