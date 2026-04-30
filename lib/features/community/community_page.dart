import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/upload_service.dart';
import 'video_player_page.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({Key? key}) : super(key: key);

  Future<void> _pickAndUpload(BuildContext context) async {
    final file = await UploadService.pickVideo();
    if (file == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No video selected')));
      return;
    }
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('Uploading video...')));
    final url = await UploadService.uploadVideoFile(file);
    if (url == null) {
      scaffold.showSnackBar(const SnackBar(content: Text('Upload failed')));
    } else {
      scaffold.showSnackBar(const SnackBar(content: Text('Upload successful')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userUid = AuthService.instance.currentUser?.uid;
    final isMod = ModerationService.isModerator(userUid);

    final stream = isMod
        ? FirebaseFirestore.instance
            .collection('community_videos')
            .orderBy('createdAt', descending: true)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('community_videos')
            .where('status', isEqualTo: 'published')
            .orderBy('createdAt', descending: true)
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          if (isMod)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Moderation',
              onPressed: () => Navigator.pushNamed(context, '/moderation'),
            )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No community videos yet'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (c, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              final title = d['title'] ?? 'Video';
              final url = d['url'] as String?;
              final uploader = d['uploaderId'] ?? 'unknown';
              final docId = doc.id;
              return ListTile(
                leading: const Icon(Icons.play_circle_fill),
                title: Text(title),
                subtitle: Text('By $uploader'),
                // show like & comment counts on trailing
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // likes count
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('community_videos')
                          .doc(docId)
                          .collection('likes')
                          .snapshots(),
                      builder: (ctx, snapLikes) {
                        final likes =
                            snapLikes.hasData ? snapLikes.data!.docs.length : 0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite,
                                size: 16, color: Colors.redAccent),
                            const SizedBox(width: 4),
                            Text('$likes'),
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    // comments count
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('community_videos')
                          .doc(docId)
                          .collection('comments')
                          .snapshots(),
                      builder: (ctx, snapComments) {
                        final comments = snapComments.hasData
                            ? snapComments.data!.docs.length
                            : 0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.comment, size: 16),
                            const SizedBox(width: 4),
                            Text('$comments'),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                onTap: url != null
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerPage(
                                videoUrl: url, title: title, videoDocId: docId),
                          ),
                        )
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'community_upload',
        child: const Icon(Icons.cloud_upload),
        onPressed: () => _pickAndUpload(context),
      ),
    );
  }
}
