/// PWA install prompt — web (beforeinstallprompt + iOS hint).
library;

import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PwaInstallController {
  PwaInstallController._();

  static final PwaInstallController instance = PwaInstallController._();

  static const _dismissKey = 'pwa_install_banner_dismissed_v1';

  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isIosManualInstall = ValueNotifier<bool>(false);

  html.BeforeInstallPromptEvent? _deferredPrompt;
  bool _initialized = false;

  bool _isStandalone() {
    try {
      if (html.window.matchMedia('(display-mode: standalone)').matches) {
        return true;
      }
      final nav = html.window.navigator;
      return (nav as dynamic).standalone == true;
    } catch (_) {
      return false;
    }
  }

  bool _isIosBrowser() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (_isStandalone()) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_dismissKey) == true) return;

    html.window.addEventListener('beforeinstallprompt', (event) {
      event.preventDefault();
      if (event is html.BeforeInstallPromptEvent) {
        _deferredPrompt = event;
        isIosManualInstall.value = false;
        visible.value = true;
      }
    });

    // iOS Safari не поддерживает beforeinstallprompt — показываем подсказку.
    if (_isIosBrowser()) {
      isIosManualInstall.value = true;
      visible.value = true;
    }
  }

  Future<void> promptInstall() async {
    final prompt = _deferredPrompt;
    if (prompt == null) return;
    await prompt.prompt();
    final choice = await prompt.userChoice;
    if (choice?['outcome'] == 'accepted') {
      visible.value = false;
      _deferredPrompt = null;
    }
  }

  Future<void> dismiss() async {
    visible.value = false;
    _deferredPrompt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKey, true);
  }
}
