// Экран комментариев к посту
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/comment_service.dart';
import '../../../services/auth_service.dart';
import '../../../models/post_model.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/report_content_dialog.dart';

class CommentsScreen extends ConsumerStatefulWidget {
  final int postId;
  final PostModel? post; // Опционально, для отображения информации о посте
  
  const CommentsScreen({
    super.key,
    required this.postId,
    this.post,
  });
  
  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<Comment> _comments = [];
  int? _replyToCommentId;
  String? _replyToAuthor;
  bool _isLoading = false;
  bool _isPosting = false;
  bool _hasMore = true;
  int _offset = 0;
  final Set<int> _expandedThreads = <int>{};
  
  @override
  void initState() {
    super.initState();
    _loadComments();
  }
  
  void _focusCommentInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commentFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  bool _isOwnComment(Comment c) {
    final me = AuthService.instance.currentUser?.id;
    return me != null && c.userId == me;
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
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить комментарии'))),
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
    final token = await AuthService.getAccessTokenForApi();
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
      final newComment = await CommentService.createComment(
        widget.postId,
        text,
        parentId: _replyToCommentId,
      );
      
      setState(() {
        _comments.insert(0, newComment);
        _commentController.clear();
        _replyToCommentId = null;
        _replyToAuthor = null;
      });
      
      // Прокручиваем к новому комментарию
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } on ApiClientException catch (e) {
      if (mounted) {
        final text = e.isContentBlocked
            ? 'Комментарий не прошёл модерацию.'
            : e.isRateLimited
                ? e.message
                : e.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleAuthError(
                e,
                fallback: 'Не удалось отправить комментарий',
                authFallback: 'Войдите, чтобы оставить комментарий',
              ),
            ),
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
    try {
      return DateFormat('HH:mm', 'ru').format(date);
    } catch (_) {
      return DateFormat('HH:mm').format(date);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final byId = <int, Comment>{for (final c in _comments) c.id: c};
    final roots = _comments.where((c) => c.parentId == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    int rootIdFor(Comment c) {
      Comment current = c;
      final visited = <int>{};
      while (current.parentId != null &&
          byId.containsKey(current.parentId) &&
          !visited.contains(current.id)) {
        visited.add(current.id);
        current = byId[current.parentId]!;
      }
      return current.id;
    }

    final repliesByRoot = <int, List<Comment>>{};
    for (final c in _comments) {
      if (c.parentId == null) continue;
      final rootId = rootIdFor(c);
      repliesByRoot.putIfAbsent(rootId, () => <Comment>[]).add(c);
    }
    for (final list in repliesByRoot.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Комментарии'),
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _buildComposerBar(context),
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
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                          children: [
                            ...roots.map((root) {
                              final replies = repliesByRoot[root.id] ?? const <Comment>[];
                              final isExpanded = _expandedThreads.contains(root.id);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CommentItem(
                                    comment: root,
                                    isOwnComment: _isOwnComment(root),
                                    onReport: () => reportCommentWithDialog(
                                      context,
                                      root.id,
                                    ),
                                    onReply: () {
                                      setState(() {
                                        _replyToCommentId = root.id;
                                        _replyToAuthor = root.authorName ?? 'Пользователь';
                                      });
                                      _focusCommentInput();
                                    },
                                    onDelete: () async {
                                      try {
                                        await CommentService.deleteComment(root.id);
                                        setState(() {
                                          _comments.removeWhere((c) => c.id == root.id);
                                        });
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                userVisibleError(e,
                                                    fallback: 'Не удалось удалить комментарий'),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  if (replies.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, bottom: 6),
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedThreads.remove(root.id);
                                            } else {
                                              _expandedThreads.add(root.id);
                                            }
                                          });
                                        },
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 20),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          isExpanded
                                              ? 'Скрыть ответы'
                                              : 'Показать ответы (${replies.length})',
                                        ),
                                      ),
                                    ),
                                  if (replies.isNotEmpty && isExpanded)
                                    ...replies.map((reply) {
                                      final parentAuthor = reply.parentId != null
                                          ? byId[reply.parentId!]?.authorName
                                          : null;
                                      final mention = (parentAuthor != null &&
                                              parentAuthor.isNotEmpty)
                                          ? '$parentAuthor, '
                                          : '';
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 18),
                                        child: _CommentItem(
                                          comment: reply,
                                          textPrefix: mention,
                                          isOwnComment: _isOwnComment(reply),
                                          onReport: () => reportCommentWithDialog(
                                            context,
                                            reply.id,
                                          ),
                                          onReply: () {
                                            setState(() {
                                              _replyToCommentId = reply.id;
                                              _replyToAuthor =
                                                  reply.authorName ?? 'Пользователь';
                                            });
                                            _focusCommentInput();
                                          },
                                          onDelete: () async {
                                            try {
                                              await CommentService.deleteComment(reply.id);
                                              setState(() {
                                                _comments.removeWhere((c) => c.id == reply.id);
                                              });
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      userVisibleError(e,
                                                          fallback:
                                                              'Не удалось удалить комментарий'),
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      );
                                    }),
                                ],
                              );
                            }),
                            if (_hasMore)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerBar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyToCommentId != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ответ для: ${_replyToAuthor ?? 'пользователя'}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _replyToCommentId = null;
                            _replyToAuthor = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _postComment(),
                      decoration: InputDecoration(
                        hintText: _replyToCommentId != null
                            ? 'Ваш ответ…'
                            : 'Написать комментарий…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _isPosting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : FilledButton(
                          onPressed: _postComment,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            minimumSize: const Size(48, 48),
                          ),
                          child: const Icon(Icons.send, size: 20),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentItem extends StatefulWidget {
  final Comment comment;
  final String textPrefix;
  final bool isOwnComment;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback? onReport;
  
  const _CommentItem({
    required this.comment,
    this.textPrefix = '',
    required this.isOwnComment,
    required this.onReply,
    required this.onDelete,
    this.onReport,
  });
  
  String _formatDate(DateTime date) {
    try {
      return DateFormat('HH:mm', 'ru').format(date);
    } catch (_) {
      return DateFormat('HH:mm').format(date);
    }
  }
  
  @override
  State<_CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<_CommentItem> {
  bool _expanded = false;

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
    final comment = widget.comment;
    final isLongText = comment.text.length > 130;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Аватар
            CircleAvatar(
              radius: 16,
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
            const SizedBox(width: 8),
            // Контент
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.authorName ?? 'Неизвестный',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.textPrefix}${comment.text}',
                    style: const TextStyle(fontSize: 14),
                        maxLines: (isLongText && !_expanded) ? 3 : null,
                        overflow: (isLongText && !_expanded)
                            ? TextOverflow.ellipsis
                            : null,
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: widget.onReply,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -3,
                          ),
                          minimumSize: const Size(0, 20),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Ответить'),
                      ),
                      if (isLongText) const SizedBox(width: 12),
                      if (isLongText)
                        TextButton(
                          onPressed: () => setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -3,
                            ),
                            minimumSize: const Size(0, 20),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_expanded ? 'Свернуть' : 'Развернуть'),
                        ),
                      const Spacer(),
                      Text(
                        _formatDate(comment.createdAt),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.isOwnComment || widget.onReport != null)
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                splashRadius: 16,
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!widget.isOwnComment && widget.onReport != null)
                            ListTile(
                              leading: const Icon(Icons.flag_outlined),
                              title: const Text('Пожаловаться'),
                              onTap: () {
                                Navigator.pop(ctx);
                                widget.onReport!();
                              },
                            ),
                          if (widget.isOwnComment)
                            ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: const Text('Удалить'),
                              onTap: () {
                                Navigator.pop(ctx);
                                widget.onDelete();
                              },
                            ),
                        ],
                      ),
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

