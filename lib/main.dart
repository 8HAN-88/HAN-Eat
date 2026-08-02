import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app_bootstrap_state.dart';
import 'app/startup_shell.dart';
import 'core/app_stability_guard.dart';
import 'core/network/haneat_http_overrides.dart';
import 'features/calls/fcm_background_handler.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppStabilityGuard.install();

    if (!kIsWeb) {
      HttpOverrides.global = HanEatHttpOverrides();
      // Android: native CallKit UI when app is backgrounded/killed.
      if (defaultTargetPlatform == TargetPlatform.android) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }
    }

    AppBootstrapState.authReady.value = false;
    AppBootstrapState.hiveReady.value = true;
    AppBootstrapState.primaryUiReady.value = false;
    AppBootstrapState.loadFullApp.value = false;

    // Лёгкий первый кадр (StartupShell), затем HanEatApp + GoRouter — иначе белый Launch Screen на iOS 26.
    runApp(
      const ProviderScope(
        child: StartupShell(),
      ),
    );
  }, AppStabilityGuard.handleZoneError);
}
