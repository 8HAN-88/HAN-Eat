import 'boot_ready_signal_stub.dart'
    if (dart.library.html) 'boot_ready_signal_web.dart' as impl;

void notifyPrimaryUiReady() {
  impl.notifyPrimaryUiReady();
}
