// Экран комментариев к посту
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/comment_service.dart';
import '../../../services/auth_service.dart';
import '../../../models/post_model.dart';

class CommentsScreen extends ConsumerStatefulWidget {
  final int postId;
  final PostModel? post; // Опционально, для отображения информации о посте
  
  const CommentsScreen({
    Key? key,
    required this.postId,
    this.post,
  }) : super(key: key);
  
  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Comment> _comments = [];
  bool _isLoading = false;
  bool _isPosting = false;
  bool _hasMore = true;
  int _offset = 0;
  
  @override
  void initState() {
    super.initState();
    _loadComments();
  }
  
  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadComments({bool refresh = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _comments = [];
        _offset = 0;
        _hasMore = true;
      }
    });
    
    try {
      final response = await CommentService.getComments(
        widget.postId,
        limit: 20,
        offset: refresh ? 0 : _offset,
      );
      
      setState(() {
        if (refresh) {
          _comments = response.comments;
        } else {
          _comments.addAll(response.comments);
        }
        _offset = _comments.length;
        _hasMore = _comments.length < response.total;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки комментариев: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isPosting) return;
    
    // Проверяем авторизацию
    final token = await AuthService.getAccessToken();
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Войдите, чтобы оставить комментарий'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    setState(() => _isPosting = true);
    
    try {
      final newComment = await CommentService.createComment(widget.postId, text);
      
      setState(() {
        _comments.insert(0, newComment);
        _commentController.clear();
      });
      
      // Прокручиваем к новому комментарию
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().contains('Not authenticated') || 
                            e.toString().contains('401')
            ? 'Войдите, чтобы оставить комментарий'
            : 'Ошибка публикации: ${e.toString().replaceAll('Exception: ', '')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      try {
        return DateFormat('d MMM yyyy', 'ru').format(date);
      } catch (e) {
        return DateFormat('d MMM yyyy').format(date);
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
          // Информация о посте (если есть)
          if (widget.post != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  if (widget.post!.author?.avatarUrl != null)
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(widget.post!.author!.avatarUrl!),
                    )
                  else
                    CircleAvatar(
                      radius: 20,
                      child: Text(
                        widget.post!.author?.name[0].toUpperCase() ?? '?',
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post!.author?.name ?? 'Неизвестный',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (widget.post!.title != null)
                          Text(
                            widget.post!.title!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Список комментариев
          Expanded(
            child: _comments.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.comment_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Нет комментариев',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Будьте первым!',
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadComments(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: false,
                          padding: const EdgeInsets.all(8),
                          itemCount: _comments.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _comments.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            
                            final comment = _comments[index];
                            return _CommentItem(
                              comment: comment,
                              onDelete: () async {
                                try {
                                  await CommentService.deleteComment(comment.id);
                                  setState(() {
                                    _comments.removeAt(index);
                                  });
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Ошибка удаления: $e')),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                      ),
          ),
          // Поле ввода комментария
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Написать комментарий...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _postComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isPosting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isPosting ? null : _postComment,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  final Comment comment;
  final VoidCallback onDelete;
  
  const _CommentItem({
    required this.comment,
    required this.onDelete,
  });
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      try {
        return DateFormat('d MMM yyyy', 'ru').format(date);
      } catch (e) {
        return DateFormat('d MMM yyyy').format(date);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Аватар
            CircleAvatar(
              radius: 20,
              backgroundImage: comment.authorAvatar != null
                  ? NetworkImage(comment.authorAvatar!)
                  : null,
              child: comment.authorAvatar == null
                  ? Text(
                      comment.authorName?[0].toUpperCase() ?? '?',
                      style: const TextStyle(fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Контент
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment.authorName ?? 'Неизвестный',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(comment.createdAt),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comment.text,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            // Кнопка удаления (только для своих комментариев)
            // TODO: проверять, является ли комментарий текущего пользователя
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Удалить'),
                    onTap: () {
                      Navigator.pop(context);
                      onDelete();
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

