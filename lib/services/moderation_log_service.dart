import 'package:cloud_firestore/cloud_firestore.dart';

class ModerationLogService {
  static Future<void> log(String action, Map<String, dynamic> details) async {
    final entry = <String, dynamic>{
      'action': action,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance.collection('moderation_logs').add(entry);
  }
}
