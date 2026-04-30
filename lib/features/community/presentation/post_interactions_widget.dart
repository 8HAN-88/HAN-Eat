import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/post.dart';
import '../../../services/post_interactions_service.dart';
import '../../../services/post_comments_service.dart';
import '../../../services/statistics_service.dart';
import '../../../services/auth_service.dart';
import 'post_comments_page.dart';

/// Виджет для взаимодействий с постом (лайки, комментарии, репосты, сохранения)
class PostInteractionsWidget extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback? onCommentsTap;

  const PostInteractionsWidget({
    super.key,
    required this.post,
    this.onCommentsTap,
  });

  @override
  ConsumerState<PostInteractionsWidget> createState() => _PostInteractionsWidgetState();
}

class _PostInteractionsWidgetState extends ConsumerState<PostInteractionsWidget> {
  bool _isLiked = false;
  bool _isDisliked = false;
  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<bool>(
      stream: PostInteractionsService.isLikedStream(widget.post.idString),
      builder: (context, likedSnapshot) {
        _isLiked = likedSnapshot.data ?? false;
        return StreamBuilder<bool>(
          stream: PostInteractionsService.isDislikedStream(widget.post.idString),
          builder: (context, dislikedSnapshot) {
            _isDisliked = dislikedSnapshot.data ?? false;
            return StreamBuilder<bool>(
              stream: PostInteractionsService.isSavedStream(widget.post.idString),
              builder: (context, savedSnapshot) {
                _isSaved = savedSnapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Лайк
                    _buildActionButton(
                      icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                      color: _isLiked ? Colors.red : null,
                      count: widget.post.reactions.likes,
                      onTap: () => PostInteractionsService.likePost(widget.post.idString),
                    ),

                    // Дизлайк
                    _buildActionButton(
                      icon: _isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                      color: _isDisliked ? Colors.blue : null,
                      count: widget.post.reactions.dislikes,
                      onTap: () => PostInteractionsService.dislikePost(widget.post.idString),
                    ),

                    // Комментарии
                    _buildActionButton(
                      icon: Icons.comment_outlined,
                      count: widget.post.reactions.comments,
                      onTap: () {
                        if (widget.onCommentsTap != null) {
                          widget.onCommentsTap!();
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostCommentsPage(postId: widget.post.idString),
                            ),
                          );
                        }
                      },
                    ),

                    // Репост
                    _buildActionButton(
                      icon: Icons.share_outlined,
                      count: widget.post.reactions.shares,
                      onTap: () => _showRepostDialog(),
                    ),

                    // Сохранение
                    IconButton(
                      icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border),
                      color: _isSaved ? Colors.amber : null,
                      onPressed: () => PostInteractionsService.savePost(widget.post.idString),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required int count,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 4),
            Text(_formatCount(count)),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }

  Future<void> _showRepostDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Репост'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Добавьте комментарий (необязательно)',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Репостнуть'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await PostInteractionsService.repostPost(
          widget.post.idString,
          text: textController.text.isEmpty ? null : textController.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пост репостнут')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
  }
}

