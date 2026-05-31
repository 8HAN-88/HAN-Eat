// Экран очереди модерации для админов
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/app_router.dart';
import '../../../../services/moderation_service.dart';
import '../../../widgets/app_empty_state.dart';

class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});
  
  @override
  ConsumerState<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen> {
  List<ModerationItem> _items = [];
  final Map<int, List<ModerationReport>> _reportsByItemId = {};
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  Object? _loadError;
  String? _selectedContentType; // post | comment
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _loadItems();
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }
  
  Future<void> _loadItems({bool refresh = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _items = [];
        _offset = 0;
        _hasMore = true;
        _loadError = null;
      }
    });

    try {
      final response = await ModerationService.getPendingItems(
        limit: 20,
        offset: refresh ? 0 : _offset,
        contentType: _selectedContentType,
      );

      final merged = refresh
          ? response.items
          : [..._items, ...response.items];

      setState(() {
        if (refresh) {
          _reportsByItemId.clear();
        }
        _items = merged;
        _offset = response.offset + response.items.length;
        _hasMore = response.hasMore;
      });

      await _hydrateReportsForItems(response.items);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
        if (_items.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                userVisibleError(e, fallback: 'Не удалось загрузить'),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadMore() async {
    await _loadItems();
  }

  Future<void> _hydrateReportsForItems(List<ModerationItem> items) async {
    final toFetch = items.where((item) {
      if (item.recentReports.isNotEmpty) return false;
      if (_reportsByItemId.containsKey(item.id)) return false;
      return item.reportsCount24h > 0 || item.reason == 'reported';
    }).toList();

    if (toFetch.isEmpty) return;

    await Future.wait(
      toFetch.map((item) async {
        try {
          final reports = await ModerationService.fetchContentReports(
            contentType: item.contentType,
            contentId: item.contentId,
          );
          if (!mounted) return;
          if (reports.isNotEmpty) {
            setState(() => _reportsByItemId[item.id] = reports);
          }
        } catch (_) {
          // Старый API без /content-reports — используем fallback из pending.
        }
      }),
    );
  }
  
  bool _isUserReport(ModerationItem item) => item.reason == 'reported';

  Future<void> _approveItem(ModerationItem item) async {
    final comment = await _showCommentDialog(
      title: _isUserReport(item)
          ? 'Оставить пост в ленте'
          : 'Одобрить контент',
      hint: 'Комментарий (опционально)',
    );
    
    if (comment == null || !mounted) return;

    try {
      await ModerationService.approveItem(
        itemId: item.id,
        comment: comment.isEmpty ? null : comment,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isUserReport(item)
                  ? 'Жалоба отклонена, пост остаётся в ленте'
                  : 'Контент одобрен',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }
  
  int? _authorId(ModerationItem item) => item.userId ?? item.author?.id;

  Future<void> _warnAuthor(ModerationItem item) async {
    final userId = _authorId(item);
    if (userId == null) return;

    final message = await _showCommentDialog(
      title: 'Предупреждение автору',
      hint: 'Текст предупреждения (опционально)',
    );
    if (!mounted || message == null) return;

    try {
      await ModerationService.warnUser(
        userId: userId,
        message: message.isEmpty ? null : message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Предупреждение отправлено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _banAuthor(ModerationItem item) async {
    final userId = _authorId(item);
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: Text('Пользователь #$userId будет заблокирован.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ModerationService.banUser(userId: userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь заблокирован')),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _hideFromRecommendations(ModerationItem item) async {
    try {
      await ModerationService.hideContent(itemId: item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скрыто из рекомендаций')),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _rejectItem(ModerationItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RejectDialog(isUserReport: _isUserReport(item)),
    );
    
    if (result == null) return;
    
    try {
      await ModerationService.rejectItem(
        itemId: item.id,
        reason: result['reason'] as String,
        comment: result['comment'] as String?,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isUserReport(item)
                  ? 'Пост убран из ленты (нарушение подтверждено)'
                  : 'Контент отклонён',
            ),
            backgroundColor: Colors.red,
          ),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }
  
  /// `null` — отмена, `''` — отправить без текста, иначе текст сообщения.
  Future<String?> _showCommentDialog({
    required String title,
    required String hint,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _ModeratorMessageDialog(
        title: title,
        hint: hint,
      ),
    );
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
  
  String _getContentTypeLabel(String type) {
    switch (type) {
      case 'post':
        return 'Пост';
      case 'comment':
        return 'Комментарий';
      case 'channel':
        return 'Канал';
      default:
        return type;
    }
  }
  
  IconData _getContentTypeIcon(String type) {
    switch (type) {
      case 'post':
        return Icons.article;
      case 'comment':
        return Icons.comment;
      case 'user_profile':
        return Icons.person;
      default:
        return Icons.help_outline;
    }
  }
  
  Color _getReasonColor(String? reason) {
    if (reason == null) return Colors.grey;
    switch (reason) {
      case 'auto_flagged':
        return Colors.orange;
      case 'spam':
        return Colors.red;
      case 'inappropriate':
        return Colors.purple;
      case 'copyright':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
  
  bool _hasAiScores(ModerationItem item) {
    return item.toxicityScore != null ||
        item.spamScore != null ||
        item.nsfwScore != null ||
        item.dangerScore != null;
  }

  Widget _scoreChip(String label, double value) {
    return Chip(
      label: Text('$label ${(value * 100).toStringAsFixed(0)}%'),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  String _getReasonLabel(String? reason) {
    if (reason == null) return 'Не указана';
    switch (reason) {
      case 'auto_flagged':
        return 'Автоматически помечено';
      case 'spam':
        return 'Спам';
      case 'inappropriate':
        return 'Неподходящий контент';
      case 'copyright':
        return 'Нарушение авторских прав';
      case 'reported':
        return 'Жалоба пользователя';
      default:
        return reason;
    }
  }

  void _openContent(ModerationItem item) {
    switch (item.contentType) {
      case 'post':
        context.push(PostFeedRoute.pathFor(item.contentId));
        return;
      case 'comment':
        final postId = item.contentPreview?['post_id'];
        if (postId is int) {
          context.push(PostCommentsRoute.pathFor(postId));
        } else if (postId is num) {
          context.push(PostCommentsRoute.pathFor(postId.toInt()));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось определить пост комментария')),
          );
        }
        return;
      case 'channel':
        context.push(ChannelDetailRoute.pathFor(item.contentId));
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Просмотр недоступен для типа «${item.contentType}»')),
        );
    }
  }

  String _openContentLabel(String contentType) {
    switch (contentType) {
      case 'post':
        return 'Открыть пост';
      case 'comment':
        return 'Открыть комментарий';
      case 'channel':
        return 'Открыть канал';
      default:
        return 'Открыть контент';
    }
  }

  List<ModerationReport> _reportsForItem(ModerationItem item) {
    if (item.recentReports.isNotEmpty) {
      return item.recentReports;
    }
    final cached = _reportsByItemId[item.id];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (item.reason != 'reported' && item.reportsCount24h <= 0) {
      return const [];
    }

    final reporterLine = item.flaggedByUser?.displayLine ??
        (item.flaggedBy != null
            ? 'Пользователь #${item.flaggedBy}'
            : 'Неизвестный пользователь');

    return [
      ModerationReport(
        id: 0,
        reason: item.reportCategory ?? 'other',
        reasonLabel: _reportCategoryLabel(item.reportCategory),
        comment: item.reportComment,
        reporter: item.flaggedByUser,
        reporterDisplayName: reporterLine,
        createdAt: item.createdAt,
      ),
    ];
  }

  String _reportCategoryLabel(String? category) {
    if (category == null || category.isEmpty) return 'Жалоба пользователя';
    const labels = {
      'spam': 'Спам',
      'harassment': 'Оскорбления',
      'nsfw': 'NSFW',
      'violence': 'Насилие',
      'misinformation': 'Ложная информация',
      'scam': 'Мошенничество',
      'inappropriate': 'Неподходящий контент',
      'copyright': 'Авторские права',
      'other': 'Другое',
    };
    return labels[category] ?? category;
  }

  Widget _buildReportDetailLines(ModerationReport report) {
    final when = report.createdAt != null
        ? _formatDate(report.createdAt!)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Жалобу отправил: ${report.reporterLine}',
          style: const TextStyle(fontSize: 13),
        ),
        if (when.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              when,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        if (report.hasComment)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13),
                children: [
                  const TextSpan(
                    text: 'Комментарий: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: report.comment),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReportsSection(ModerationItem item) {
    final reports = _reportsForItem(item);
    if (reports.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Жалобы (${reports.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...reports.map((report) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Причина: ${report.reasonLabel}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildReportDetailLines(report),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Очередь модерации'),
        actions: [
          // Фильтр по типу контента
          PopupMenuButton<String?>(
            initialValue: _selectedContentType,
            onSelected: (value) {
              setState(() {
                _selectedContentType = value;
              });
              _loadItems(refresh: true);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Все типы'),
              ),
              const PopupMenuItem(
                value: 'post',
                child: Text('Посты'),
              ),
              const PopupMenuItem(
                value: 'comment',
                child: Text('Комментарии'),
              ),
              const PopupMenuItem(
                value: 'channel',
                child: Text('Каналы'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list),
                  const SizedBox(width: 4),
                  Text(_selectedContentType ?? 'Все'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadItems(refresh: true),
        child: _items.isEmpty && !_isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: _loadError != null
                        ? AppEmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Не удалось загрузить очередь',
                            subtitle: userVisibleError(
                              _loadError!,
                              fallback: 'Проверьте сеть',
                            ),
                            action: FilledButton(
                              onPressed: () => _loadItems(refresh: true),
                              child: const Text('Повторить'),
                            ),
                          )
                        : const AppEmptyState(
                            icon: Icons.check_circle_outline,
                            title: 'Очередь пуста',
                            subtitle: 'Нет элементов на модерации',
                          ),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  
                  final item = _items[index];
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ExpansionTile(
                      leading: Icon(
                        _getContentTypeIcon(item.contentType),
                        color: _getReasonColor(item.reason),
                      ),
                      title: Text(
                        '${_getContentTypeLabel(item.contentType)} #${item.contentId}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.author != null)
                            Text('Автор: ${item.author!.name}'),
                          if (item.reason != null)
                            Chip(
                              label: Text(
                                _getReasonLabel(item.reason),
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: _getReasonColor(item.reason)
                                  .withValues(alpha: 0.1),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          Text(
                            _formatDate(item.createdAt),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          if (item.reportsCount24h > 0)
                            Text(
                              'Жалоб за 24ч: ${item.reportsCount24h}',
                              style: TextStyle(
                                color: Colors.orange[800],
                                fontSize: 12,
                              ),
                            ),
                          if (item.aiDecision != null)
                            Text(
                              'AI: ${item.aiDecision}',
                              style: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                      children: [
                        _buildReportsSection(item),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openContent(item),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(_openContentLabel(item.contentType)),
                          ),
                        ),
                        if (_hasAiScores(item))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (item.toxicityScore != null)
                                  _scoreChip('Токс.', item.toxicityScore!),
                                if (item.spamScore != null)
                                  _scoreChip('Спам', item.spamScore!),
                                if (item.nsfwScore != null)
                                  _scoreChip('NSFW', item.nsfwScore!),
                                if (item.dangerScore != null)
                                  _scoreChip('Опасн.', item.dangerScore!),
                              ],
                            ),
                          ),
                        // Предпросмотр контента
                        if (item.contentPreview != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Предпросмотр:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (item.contentPreview!['title'] != null)
                                  Text(
                                    'Заголовок: ${item.contentPreview!['title']}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                if (item.contentPreview!['description'] != null)
                                  Text(
                                    'Описание: ${item.contentPreview!['description']}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                if (item.contentPreview!['text'] != null)
                                  Text(
                                    'Текст: ${item.contentPreview!['text']}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                              ],
                            ),
                          ),
                        if (_authorId(item) != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _warnAuthor(item),
                                  icon: const Icon(Icons.warning_amber_outlined, size: 18),
                                  label: const Text('Предупредить'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _banAuthor(item),
                                  icon: const Icon(Icons.block, size: 18),
                                  label: const Text('Бан'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                ),
                                if (item.contentType == 'post')
                                  OutlinedButton.icon(
                                    onPressed: () => _hideFromRecommendations(item),
                                    icon: const Icon(Icons.visibility_off, size: 18),
                                    label: const Text('Скрыть из ленты'),
                                  ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _rejectItem(item),
                                icon: const Icon(Icons.close, size: 18),
                                label: Text(
                                  _isUserReport(item)
                                      ? 'Удалить пост'
                                      : 'Отклонить',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => _approveItem(item),
                                icon: const Icon(Icons.check, size: 18),
                                label: Text(
                                  _isUserReport(item)
                                      ? 'Оставить пост'
                                      : 'Одобрить',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ModeratorMessageDialog extends StatefulWidget {
  const _ModeratorMessageDialog({
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  State<_ModeratorMessageDialog> createState() => _ModeratorMessageDialogState();
}

class _ModeratorMessageDialogState extends State<_ModeratorMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
        autofocus: true,
        textInputAction: TextInputAction.done,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({this.isUserReport = false});

  final bool isUserReport;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  String _selectedReason = 'spam';
  final _commentController = TextEditingController();
  
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final dialogWidth = MediaQuery.sizeOf(context).width * 0.88;

    return AlertDialog(
      title: Text(
        widget.isUserReport
            ? 'Удалить пост из ленты'
            : 'Отклонить контент',
      ),
      content: SizedBox(
        width: dialogWidth.clamp(280.0, 400.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Причина отклонения:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedReason,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'spam',
                    child: Text('Спам', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'inappropriate',
                    child: Text(
                      'Неподходящий контент',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'copyright',
                    child: Text(
                      'Нарушение авторских прав',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Другое', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedReason = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (опционально)',
                  hintText: 'Добавьте комментарий...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'reason': _selectedReason,
              'comment': _commentController.text.trim().isEmpty
                  ? null
                  : _commentController.text.trim(),
            });
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(widget.isUserReport ? 'Удалить пост' : 'Отклонить'),
        ),
      ],
    );
  }
}
