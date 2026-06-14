/// PWA install prompt — stub для mobile/desktop.
library;

import 'package:flutter/foundation.dart';

class PwaInstallController {
  PwaInstallController._();

  static final PwaInstallController instance = PwaInstallController._();

  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isIosManualInstall = ValueNotifier<bool>(false);

  Future<void> init() async {}

  Future<void> promptInstall() async {}

  Future<void> dismiss() async {}
}
