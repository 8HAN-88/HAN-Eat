import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/community_service.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';

class CommentsPage extends StatefulWidget {
  final String videoDocId;
  const CommentsPage({required this.videoDocId, Key? key}) : super(key: key);

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final currentUid = AuthService.instance.currentUser?.uid;
    final isMod = ModerationService.isModerator(currentUid);

    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: CommunityService.commentsStream(widget.videoDocId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint('Error in comments StreamBuilder: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('Ошибка загрузки комментариев: ${snapshot.error}'),
                      ],
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('Нет комментариев'));
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty)
                  return const Center(child: Text('Нет комментариев'));
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (c, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final author = data['authorId'] ?? 'anon';
                    final text = data['text'] ?? '';
                    final status = data['status'] ?? 'published';
                    return ListTile(
                      title: Text(text),
                      subtitle: Text(
                          'by $author ${status == 'flagged' ? '• FLAGGED' : ''}'),
                      trailing: isMod
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              if (status == 'flagged')
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  onPressed: () async {
                                    await CommunityService.setCommentStatus(
                                        widget.videoDocId, doc.id, 'published');
                                  },
                                ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  await CommunityService.deleteComment(
                                      widget.videoDocId, doc.id);
                                },
                              ),
                            ])
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration:
                        const InputDecoration(hintText: 'Write a comment'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final text = _ctrl.text.trim();
                    if (text.isEmpty) return;
                    final uid = AuthService.instance.currentUser?.uid;
                    if (uid == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sign in to comment')));
                      return;
                    }
                    final mod = ModerationService.moderateText(text);
                    final status = mod.flagged ? 'flagged' : 'published';
                    await CommunityService.addComment(
                        widget.videoDocId, uid, text,
                        status: status);
                    _ctrl.clear();
                    if (mod.flagged) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Comment flagged for review')));
                    }
                  },
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
