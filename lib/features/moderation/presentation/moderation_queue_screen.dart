// Экран очереди модерации для админов
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/moderation_service.dart';
import 'package:intl/intl.dart';

class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});
  
  @override
  ConsumerState<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen> {
  List<ModerationItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  String? _selectedContentType; // post | comment | user_profile
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
        _nextCursor = null;
        _hasMore = true;
      }
    });
    
    try {
      final response = await ModerationService.getPendingItems(
        limit: 20,
        cursor: refresh ? null : _nextCursor,
        contentType: _selectedContentType,
      );
      
      setState(() {
        if (refresh) {
          _items = response.items;
        } else {
          _items.addAll(response.items);
        }
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
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
  
  Future<void> _approveItem(ModerationItem item) async {
    final comment = await _showCommentDialog(
      title: 'Одобрить контент',
      hint: 'Комментарий (опционально)',
    );
    
    if (comment == null && mounted) {
      // Пользователь отменил
      return;
    }
    
    try {
      await ModerationService.approveItem(
        itemId: item.id,
        comment: comment,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Контент одобрен'),
            backgroundColor: Colors.green,
          ),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  Future<void> _rejectItem(ModerationItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RejectDialog(),
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
          const SnackBar(
            content: Text('Контент отклонен'),
            backgroundColor: Colors.red,
          ),
        );
        _loadItems(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }
  
  Future<String?> _showCommentDialog({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(context).pop(text.isEmpty ? null : text);
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
    
    controller.dispose();
    return result;
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
      case 'user_profile':
        return 'Профиль';
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
      default:
        return reason;
    }
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
                value: 'user_profile',
                child: Text('Профили'),
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
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Нет элементов на модерации',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
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
                                  .withOpacity(0.1),
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
                        ],
                      ),
                      children: [
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
                        // Действия
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _rejectItem(item),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Отклонить'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => _approveItem(item),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Одобрить'),
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

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();
  
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
    return AlertDialog(
      title: const Text('Отклонить контент'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Причина отклонения:'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedReason,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'spam', child: Text('Спам')),
              DropdownMenuItem(
                value: 'inappropriate',
                child: Text('Неподходящий контент'),
              ),
              DropdownMenuItem(
                value: 'copyright',
                child: Text('Нарушение авторских прав'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Другое')),
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
            ),
            maxLines: 3,
          ),
        ],
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
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}
