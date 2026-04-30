import 'package:flutter/material.dart';
import '../../../services/post_comments_service.dart';
import '../../../services/auth_service.dart';

/// Экран комментариев к посту
class PostCommentsPage extends StatefulWidget {
  final String postId;

  const PostCommentsPage({
    super.key,
    required this.postId,
  });

  @override
  State<PostCommentsPage> createState() => _PostCommentsPageState();
}

class _PostCommentsPageState extends State<PostCommentsPage> {
  final _textController = TextEditingController();
  String? _replyingToCommentId;
  String? _replyingToAuthor;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_textController.text.trim().isEmpty) return;

    try {
      await PostCommentsService.addComment(
        widget.postId,
        _textController.text.trim(),
        parentCommentId: _replyingToCommentId,
      );
      _textController.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToAuthor = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Комментарии'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<PostComment>>(
              stream: PostCommentsService.getComments(widget.postId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Ошибка: ${snapshot.error}'));
                }

                final comments = snapshot.data ?? [];
                if (comments.isEmpty) {
                  return const Center(child: Text('Пока нет комментариев'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) => _buildComment(comments[index]),
                );
              },
            ),
          ),
          if (_replyingToCommentId != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[200],
              child: Row(
                children: [
                  Expanded(
                    child: Text('Ответ на: $_replyingToAuthor'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _replyingToCommentId = null;
                        _replyingToAuthor = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Написать комментарий...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComment(PostComment comment) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: comment.authorAvatar != null
                      ? NetworkImage(comment.authorAvatar!)
                      : null,
                  child: comment.authorAvatar == null
                      ? Text(comment.authorName?[0].toUpperCase() ?? '?')
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.authorName ?? 'Пользователь',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatDate(comment.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment.text),
            const SizedBox(height: 8),
            Row(
              children: [
                StreamBuilder<bool>(
                  stream: PostCommentsService.isCommentLikedStream(
                    widget.postId,
                    comment.id,
                  ),
                  builder: (context, snapshot) {
                    final isLiked = snapshot.data ?? false;
                    return InkWell(
                      onTap: () => PostCommentsService.likeComment(
                        widget.postId,
                        comment.id,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: isLiked ? Colors.red : null,
                          ),
                          const SizedBox(width: 4),
                          Text('${comment.likes}'),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _replyingToCommentId = comment.id;
                      _replyingToAuthor = comment.authorName;
                    });
                  },
                  child: const Text('Ответить'),
                ),
              ],
            ),
            // Ответы на комментарий
            StreamBuilder<List<PostComment>>(
              stream: PostCommentsService.getCommentReplies(
                widget.postId,
                comment.id,
              ),
              builder: (context, repliesSnapshot) {
                final replies = repliesSnapshot.data ?? [];
                if (replies.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8),
                  child: Column(
                    children: replies.map((reply) => _buildComment(reply)).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}

