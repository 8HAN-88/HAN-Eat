import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/community_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';
import '../../../services/moderation_service.dart';
import 'package:intl/intl.dart';

/// Улучшенная страница комментариев с ответами и лайками
class EnhancedCommentsPage extends StatefulWidget {
  final String videoDocId;
  const EnhancedCommentsPage({required this.videoDocId, super.key});

  @override
  State<EnhancedCommentsPage> createState() => _EnhancedCommentsPageState();
}

class _EnhancedCommentsPageState extends State<EnhancedCommentsPage> {
  final _ctrl = TextEditingController();
  String? _replyingToCommentId;
  String? _replyingToAuthor;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Комментарии'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: CommunityService.commentsStream(widget.videoDocId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Фильтруем только основные комментарии (без parentCommentId)
                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['parentCommentId'] == null;
                }).toList();
                
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Пока нет комментариев'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _CommentItem(
                      videoDocId: widget.videoDocId,
                      commentDoc: doc,
                      onReply: (commentId, author) {
                        setState(() {
                          _replyingToCommentId = commentId;
                          _replyingToAuthor = author;
                        });
                        _ctrl.clear();
                        FocusScope.of(context).requestFocus(
                          FocusNode()..requestFocus(),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Индикатор ответа
          if (_replyingToCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey[200],
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ответ на: $_replyingToAuthor',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _replyingToCommentId = null;
                        _replyingToAuthor = null;
                      });
                    },
                    child: const Text('Отмена'),
                  ),
                ],
              ),
            ),
          // Поле ввода
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: _replyingToCommentId != null
                          ? 'Напишите ответ...'
                          : 'Напишите комментарий...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final text = _ctrl.text.trim();
                    if (text.isEmpty) return;
                    final uid = currentUid;
                    if (uid == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Войдите, чтобы комментировать'),
                          ),
                        );
                      }
                      return;
                    }
                    final mod = ModerationService.moderateText(text);
                    final status = mod.flagged ? 'flagged' : 'published';
                    await CommunityService.addComment(
                      widget.videoDocId,
                      uid,
                      text,
                      status: status,
                      parentCommentId: _replyingToCommentId,
                    );
                    if (mounted) {
                      _ctrl.clear();
                      setState(() {
                        _replyingToCommentId = null;
                        _replyingToAuthor = null;
                      });
                      if (mod.flagged) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Комментарий отправлен на модерацию'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  const _CommentItem({
    required this.videoDocId,
    required this.commentDoc,
    required this.onReply,
  });

  final String videoDocId;
  final DocumentSnapshot commentDoc;
  final Function(String commentId, String author) onReply;

  @override
  Widget build(BuildContext context) {
    final data = commentDoc.data() as Map<String, dynamic>;
    final authorId = data['authorId'] as String? ?? 'anon';
    final text = data['text'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final status = data['status'] as String? ?? 'published';
    final commentId = commentDoc.id;
    final currentUid = AuthService.instance.currentUser?.uid;

    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('d MMM, HH:mm', 'ru');
    } catch (e) {
      dateFormat = DateFormat('d MMM, HH:mm');
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(authorId.substring(0, 1).toUpperCase()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _getAuthorName(authorId),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? authorId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      if (createdAt != null)
                        Text(
                          dateFormat?.format(createdAt.toDate()) ??
                              createdAt.toDate().toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                if (status == 'flagged')
                  Chip(
                    label: const Text('На модерации'),
                    avatar: const Icon(Icons.flag, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 8),
            Row(
              children: [
                // Лайк комментария
                StreamBuilder<bool>(
                  stream: CommunityService.isCommentLikedStream(
                    videoDocId,
                    commentId,
                    currentUid,
                  ),
                  builder: (context, snapshot) {
                    final isLiked = snapshot.data ?? false;
                    return StreamBuilder<int>(
                      stream: CommunityService.commentLikesStream(
                        videoDocId,
                        commentId,
                      ),
                      builder: (context, snapshot) {
                        final likes = snapshot.data ?? 0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                color: isLiked ? Colors.red : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () {
                                if (currentUid != null) {
                                  CommunityService.toggleCommentLike(
                                    videoDocId,
                                    commentId,
                                    currentUid,
                                  );
                                }
                              },
                            ),
                            if (likes > 0)
                              Text(
                                '$likes',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Ответ
                TextButton.icon(
                  onPressed: () {
                    onReply(commentId, authorId);
                  },
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('Ответить'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const Spacer(),
                // Репорт
                IconButton(
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  onPressed: () {
                    _showReportDialog(context, videoDocId, commentId, currentUid);
                  },
                  tooltip: 'Пожаловаться',
                ),
              ],
            ),
            // Ответы на комментарий
            StreamBuilder<QuerySnapshot>(
              stream: CommunityService.commentRepliesStream(
                videoDocId,
                commentId,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                final replies = snapshot.data!.docs;
                return Container(
                  margin: const EdgeInsets.only(top: 8, left: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Ответы (${replies.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...replies.map((replyDoc) {
                        return _ReplyItem(
                          videoDocId: videoDocId,
                          replyDoc: replyDoc,
                        );
                      }).toList(),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getAuthorName(String authorId) async {
    try {
      final profile = await UserService.instance.loadPublicProfile(authorId);
      return profile.displayName;
    } catch (e) {
      return authorId;
    }
  }

  void _showReportDialog(
    BuildContext context,
    String videoDocId,
    String commentId,
    String? currentUid,
  ) {
    if (currentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы пожаловаться')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Пожаловаться на комментарий'),
        content: const Text('Вы уверены, что хотите пожаловаться на этот комментарий?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await CommunityService.reportComment(
                videoDocId,
                commentId,
                currentUid,
              );
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Жалоба отправлена')),
                );
              }
            },
            child: const Text('Пожаловаться'),
          ),
        ],
      ),
    );
  }
}

class _ReplyItem extends StatelessWidget {
  const _ReplyItem({
    required this.videoDocId,
    required this.replyDoc,
  });

  final String videoDocId;
  final DocumentSnapshot replyDoc;

  @override
  Widget build(BuildContext context) {
    final data = replyDoc.data() as Map<String, dynamic>;
    final authorId = data['authorId'] as String? ?? 'anon';
    final text = data['text'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;

    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('d MMM, HH:mm', 'ru');
    } catch (e) {
      dateFormat = DateFormat('d MMM, HH:mm');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            child: Text(authorId.substring(0, 1).toUpperCase()),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String>(
                  future: _getAuthorName(authorId),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? authorId,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                Text(
                  text,
                  style: const TextStyle(fontSize: 13),
                ),
                if (createdAt != null)
                  Text(
                    dateFormat?.format(createdAt.toDate()) ??
                        createdAt.toDate().toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getAuthorName(String authorId) async {
    try {
      final profile = await UserService.instance.loadPublicProfile(authorId);
      return profile.displayName;
    } catch (e) {
      return authorId;
    }
  }
}

