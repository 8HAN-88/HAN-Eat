import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app/app_variant.dart';
import '../services/auth_service.dart';
import '../widgets/app_brand_logo.dart';
import 'app_router.dart';

class WebSessionLandingScreen extends StatefulWidget {
  const WebSessionLandingScreen({super.key});

  @override
  State<WebSessionLandingScreen> createState() => _WebSessionLandingScreenState();
}

class _WebSessionLandingScreenState extends State<WebSessionLandingScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_continueToTarget());
    });
  }

  Future<void> _continueToTarget() async {
    if (!mounted || _navigated) return;
    _navigated = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    final user = AuthService.instance.currentUser;
    if (user == null) {
      context.go(LoginRoute.path);
      return;
    }
    if (!user.emailVerified) {
      context.go(VerifyEmailRoute.withEmail(user.email));
      return;
    }
    if (user.legalConsentRequired) {
      context.go(LegalConsentRoute.path);
      return;
    }

    final destination =
        AppVariant.current.isKitchen ? MenuRoute.path : WebSocialHomeRoute.path;
    context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    const canvas = Color(0xFF0F1319);
    return const Scaffold(
      backgroundColor: canvas,
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
                SizedBox(height: 28),
                CircularProgressIndicator(
                  color: Color(0xFF2AABEE),
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
