import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'call_kit_bridge.dart';

/// Top-level FCM background handler (Android). Shows native CallKit UI.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('FCM background Firebase init: $e');
  }
  try {
    await CallKitBridge.showFromPushData(message.data);
  } catch (e) {
    debugPrint('FCM background CallKit show failed: $e');
  }
}
