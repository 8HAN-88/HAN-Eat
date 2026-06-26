import Foundation

/// Безопасная инициализация Firebase до Dart (FCM / Crashlytics на iOS 26).
enum FirebaseBootstrap {
  static func configureIfNeeded() {
    if !HANEatConfigureFirebase() {
      NSLog("FirebaseBootstrap: native configure skipped after failure")
    }
  }
}
