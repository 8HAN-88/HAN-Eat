import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/community_service.dart';

class ModeratorPage extends StatelessWidget {
  const ModeratorPage({Key? key}) : super(key: key);

  Widget _buildFlaggedVideos() {
    // Include both flagged and deleted for moderation
    final stream = FirebaseFirestore.instance
        .collection('community_videos')
        .where('status', whereIn: ['flagged', 'deleted'])
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return const Center(child: Text('No flagged or deleted videos'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (c, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            final title = d['title'] ?? 'Video';
            final uploader = d['uploaderId'] ?? 'unknown';
            final reason = d['moderationReason'] ?? '';
            final status = d['status'] ?? '';
            final id = doc.id;
            return ListTile(
              title: Text(title),
              subtitle: Text('By $uploader\nReason: $reason\nStatus: $status'),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == 'flagged') ...[
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve',
                      onPressed: () async {
                        await CommunityService.setVideoStatus(id, 'published');
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Video approved')));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Soft Delete',
                      onPressed: () async {
                        await CommunityService.softDeleteVideo(id);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Video soft-deleted')));
                      },
                    ),
                  ] else if (status == 'deleted') ...[
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.orange),
                      tooltip: 'Restore',
                      onPressed: () async {
                        await CommunityService.restoreVideo(id);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Video restored')));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      tooltip: 'Permanently Delete',
                      onPressed: () async {
                        await CommunityService.permanentlyDeleteVideo(id);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Video permanently deleted')));
                      },
                    ),
                  ]
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFlaggedComments() {
    // collectionGroup to find flagged comments across all videos
    final stream = FirebaseFirestore.instance
        .collectionGroup('comments')
        .where('status', isEqualTo: 'flagged')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return const Center(child: Text('No flagged comments'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (c, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final text = data['text'] ?? '';
            final author = data['authorId'] ?? 'anon';
            final commentId = doc.id;
            // parent video doc id is doc.reference.parent.parent
            final parentRef = doc.reference.parent.parent;
            final videoDocId = parentRef?.id;
            return ListTile(
              title: Text(text),
              subtitle: Text('By $author\nVideo: ${videoDocId ?? 'unknown'}'),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: 'Approve',
                    onPressed: videoDocId == null
                        ? null
                        : () async {
                            await CommunityService.setCommentStatus(
                                videoDocId, commentId, 'published');
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Comment approved')));
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: videoDocId == null
                        ? null
                        : () async {
                            await CommunityService.deleteComment(
                                videoDocId, commentId);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Comment deleted')));
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderation'),
          bottom:
              const TabBar(tabs: [Tab(text: 'Videos'), Tab(text: 'Comments')]),
        ),
        body: TabBarView(
          children: [
            _buildFlaggedVideos(),
            _buildFlaggedComments(),
          ],
        ),
      ),
    );
  }
}
