import 'package:flutter/foundation.dart';

/// Состояние фоновой инициализации (не блокирует первый кадр UI).
class AppBootstrapState {
  AppBootstrapState._();

  /// Auth + минимум для навигации после входа.
  static final ValueNotifier<bool> authReady = ValueNotifier(false);

  /// Hive.initFlutter завершён — можно открывать боксы.
  static final ValueNotifier<bool> hiveReady = ValueNotifier(false);

  /// Hive, Firebase, локальные сервисы.
  static final ValueNotifier<bool> servicesReady = ValueNotifier(false);

  /// Главный UI после auth — Hive подгружается в фоне, не блокирует вход.
  static bool get canOpenMainShell => authReady.value;
}
