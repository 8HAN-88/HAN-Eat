import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'moderation_service.dart';

class UploadService {
  static final _picker = ImagePicker();

  // Pick a video from gallery (returns XFile or null)
  static Future<XFile?> pickVideo() async {
    try {
      final XFile? file = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 10));
      return file;
    } catch (e) {
      // ignore errors here; caller shows snackbar
      return null;
    }
  }

  // Upload picked video file to Firebase Storage and create metadata in Firestore.
  // Returns download URL or null on failure.
  static Future<String?> uploadVideoFile(XFile file, {String? title}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anonymous';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = file.path.split('.').last;
      final storagePath = 'community_videos/$uid/$timestamp.$ext';

      final ref = fb_storage.FirebaseStorage.instance.ref().child(storagePath);
      final uploadTask = ref.putFile(File(file.path));

      await uploadTask.whenComplete(() => {});
      final downloadUrl = await ref.getDownloadURL();

      // moderation on title/name
      final titleUsed = (title ?? file.name);
      final mod = ModerationService.moderateText(titleUsed);

      // store metadata in Firestore, include moderation status if flagged
      await FirebaseFirestore.instance.collection('community_videos').add({
        'url': downloadUrl,
        'title': titleUsed,
        'uploaderId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': mod.flagged ? 'flagged' : 'published',
        'moderationReason': mod.reason,
      });

      return downloadUrl;
    } catch (e) {
      return null;
    }
  }
}
