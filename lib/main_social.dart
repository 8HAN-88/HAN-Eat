import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app_bootstrap_state.dart';
import 'app/startup_shell.dart';
import 'core/app_stability_guard.dart';
import 'core/network/haneat_http_overrides.dart';

/// Entry point for HanWe (social) build.
/// Use: flutter run -t lib/main_social.dart --dart-define=APP_VARIANT=social
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppStabilityGuard.install();

    if (!kIsWeb) {
      HttpOverrides.global = HanEatHttpOverrides();
    }

    AppBootstrapState.authReady.value = false;
    AppBootstrapState.hiveReady.value = true;

    runApp(
      const ProviderScope(
        child: StartupShell(),
      ),
    );
  }, AppStabilityGuard.handleZoneError);
}
