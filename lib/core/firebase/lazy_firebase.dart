import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Безопасный доступ к Firebase — не трогает native SDK до [Firebase.initializeApp].
class LazyFirebase {
  LazyFirebase._();

  static bool get isReady => Firebase.apps.isNotEmpty;

  static FirebaseFirestore get firestore {
    if (!isReady) {
      throw StateError('Firebase not initialized');
    }
    return FirebaseFirestore.instance;
  }

  static FirebaseStorage get storage {
    if (!isReady) {
      throw StateError('Firebase not initialized');
    }
    return FirebaseStorage.instance;
  }
}
