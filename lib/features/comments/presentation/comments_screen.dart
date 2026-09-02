// Экран комментариев к посту
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../services/comment_service.dart';
import '../../../services/auth_service.dart';
import '../../../models/post_model.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/report_content_dialog.dart';

class CommentsScreen extends ConsumerStatefulWidget {
  final int postId;
  final PostModel? post; // Опционально, для отображения информации о посте

  /// When true, render as a bottom-sheet body (no Scaffold AppBar).
  final bool asSheet;

  /// Fires after load / post / delete with the current comments total.
  final ValueChanged<int>? onCommentsCountChanged;

  const CommentsScreen({
    super.key,
    required this.postId,
    this.post,
    this.asSheet = false,
    this.onCommentsCountChanged,
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
  String? _loadError;
  bool _isPosting = false;
  bool _hasMore = true;
  int _offset = 0;
  int _listedTotal = 0;
  final Set<int> _expandedThreads = <int>{};

  @override
  void initState() {
    super.initState();
    _listedTotal = widget.post?.commentsCount ?? 0;
    _scrollController.addListener(_onScroll);
    _loadComments();
  }

  void _emitCount() {
    widget.onCommentsCountChanged?.call(_listedTotal);
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadComments();
    }
  }

  void _focusCommentInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commentFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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
      _loadError = null;
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
        _listedTotal = response.total;
        _offset = _comments.length;
        _hasMore = _comments.length < _listedTotal;
      });
      _emitCount();
    } catch (e) {
      if (mounted) {
        final message = userVisibleError(
          e,
          fallback: 'Не удалось загрузить комментарии',
        );
        setState(() {
          if (_comments.isEmpty) _loadError = message;
        });
        if (_comments.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
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
        _listedTotal += 1;
        _offset = _comments.length;
        _hasMore = _comments.length < _listedTotal;
      });
      _emitCount();

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
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось отправить комментарий',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  Future<void> _deleteComment(Comment target) async {
    try {
      await CommentService.deleteComment(target.id);
      if (!mounted) return;
      final removeIds = <int>{target.id};
      if (target.parentId == null) {
        for (final c in _comments) {
          if (c.parentId == target.id) removeIds.add(c.id);
        }
      }
      setState(() {
        _comments.removeWhere((c) => removeIds.contains(c.id));
        _listedTotal -= removeIds.length;
        if (_listedTotal < 0) _listedTotal = 0;
        _offset = _comments.length;
      });
      _emitCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось удалить комментарий'),
            ),
          ),
        );
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

    final scheme = Theme.of(context).colorScheme;
    final listBody = Column(
      children: [
        if (widget.asSheet)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Комментарии',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context, rootNavigator: true)
                      .maybePop(_listedTotal),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        // Информация о посте (если есть) — hide in sheet to keep IG-like density
        if (widget.post != null && !widget.asSheet)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant, width: 0.7),
            ),
            child: Row(
              children: [
                AppUserAvatar(
                  imageUrl: widget.post!.author?.avatarUrl,
                  displayName: widget.post!.author?.name ?? '?',
                  radius: 20,
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
                            color: scheme.onSurfaceVariant,
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
              : _loadError != null && _comments.isEmpty
                  ? AppEmptyState(
                      icon: Icons.wifi_off_outlined,
                      title: 'Не удалось загрузить комментарии',
                      subtitle: _loadError,
                      action: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton(
                            onPressed: () => _loadComments(refresh: true),
                            child: const Text('Повторить'),
                          ),
                          if (widget.asSheet) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
                              child: const Text('Закрыть'),
                            ),
                          ],
                        ],
                      ),
                    )
              : _comments.isEmpty
                  ? AppEmptyState(
                      icon: Icons.comment_outlined,
                      title: 'Нет комментариев',
                      subtitle: 'Будьте первым!',
                      action: FilledButton(
                        onPressed: _focusCommentInput,
                        child: const Text('Написать'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadComments(refresh: true),
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        children: [
                          ...roots.map((root) {
                            final replies =
                                repliesByRoot[root.id] ?? const <Comment>[];
                            final isExpanded =
                                _expandedThreads.contains(root.id);
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
                                      _replyToAuthor =
                                          root.authorName ?? 'Пользователь';
                                    });
                                    _focusCommentInput();
                                  },
                                  onDelete: () => _deleteComment(root),
                                ),
                                if (replies.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 12, bottom: 6),
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
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
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
                                      final parentAuthor = reply.parentId !=
                                              null
                                          ? byId[reply.parentId!]?.authorName
                                          : null;
                                      final mention = (parentAuthor != null &&
                                              parentAuthor.isNotEmpty)
                                          ? '$parentAuthor, '
                                          : '';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(left: 18),
                                        child: _CommentItem(
                                          comment: reply,
                                          textPrefix: mention,
                                          isOwnComment: _isOwnComment(reply),
                                          onReport: () =>
                                              reportCommentWithDialog(
                                            context,
                                            reply.id,
                                          ),
                                          onReply: () {
                                            setState(() {
                                              _replyToCommentId = reply.id;
                                              _replyToAuthor =
                                                  reply.authorName ??
                                                      'Пользователь';
                                            });
                                            _focusCommentInput();
                                          },
                                          onDelete: () =>
                                              _deleteComment(reply),
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
    );

    if (widget.asSheet) {
      return Material(
        color: scheme.surface,
        child: Column(
          children: [
            Expanded(child: listBody),
            _buildComposerBar(context, includeSafeArea: true),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.telegramChatBgDark
          : AppColors.telegramChatBgLight,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('Комментарии'),
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _buildComposerBar(context),
      body: listBody,
    );
  }

  Widget _buildComposerBar(
    BuildContext context, {
    bool includeSafeArea = true,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
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
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
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
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
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
                  : IconButton.filled(
                      onPressed: _postComment,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(46, 46),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 20),
                    ),
            ],
          ),
        ],
      ),
    );
    return Material(
      elevation: 0,
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: includeSafeArea ? SafeArea(top: false, child: content) : content,
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: scheme.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 9, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Аватар
              AppUserAvatar(
                imageUrl: comment.authorAvatar,
                displayName: comment.authorName ?? '?',
                radius: 16,
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
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
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
                            color: scheme.onSurfaceVariant,
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
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 24),
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
      ),
    );
  }
}
