// Light Flutter web plugin registrant for HAN-Eat cold start.
//
// Replaces the generated web_plugin_registrant.dart during release builds so
// iPhone Safari does not download video/WebView/Firebase plugin code before
// login. Heavy plugins are registered later from
// package:han_eat/app/web_plugins_heavy.dart after the full app chunk loads.
//
// @dart = 2.13
// ignore_for_file: type=lint

import 'package:app_links_web/app_links_web.dart';
import 'package:connectivity_plus/src/connectivity_plus_web.dart';
import 'package:flutter_web_auth_2/src/web.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:package_info_plus/src/package_info_plus_web.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
  AppLinksPluginWeb.registerWith(registrar);
  ConnectivityPlusWebPlugin.registerWith(registrar);
  FlutterWebAuth2WebPlugin.registerWith(registrar);
  GoogleSignInPlugin.registerWith(registrar);
  PackageInfoPlusWebPlugin.registerWith(registrar);
  SharedPreferencesPlugin.registerWith(registrar);
  UrlLauncherPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
