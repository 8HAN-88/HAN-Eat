import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/subscription_service.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../../widgets/app_empty_state.dart';

/// Запланированные публикации (Creator / Pro).
class ScheduledPostsScreen extends ConsumerStatefulWidget {
  const ScheduledPostsScreen({super.key});

  @override
  ConsumerState<ScheduledPostsScreen> createState() =>
      _ScheduledPostsScreenState();
}

class _ScheduledPostsScreenState extends ConsumerState<ScheduledPostsScreen> {
  bool _loading = true;
  String? _error;
  List<ScheduledPostSummary> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await SubscriptionService.getSubscriptionStatus();
      if (!status.hasCreator) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'creator_required';
        });
        return;
      }
      final posts = await ChannelService.getScheduledPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить');
        _loading = false;
      });
    }
  }

  Future<void> _reschedule(ScheduledPostSummary post) async {
    final initial = post.scheduledPublishAt ?? DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите время в будущем')),
      );
      return;
    }
    try {
      await ChannelService.rescheduleScheduledPost(
        postId: post.id,
        scheduledPublishAt: scheduled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Время публикации обновлено')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _cancel(ScheduledPostSummary post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить публикацию?'),
        content: Text(
          post.title?.isNotEmpty == true
              ? '«${post.title}» не будет опубликован.'
              : 'Пост не будет опубликован по расписанию.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChannelService.cancelScheduledPost(post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Публикация отменена')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(subscriptionStatusProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Запланированные посты'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(status),
    );
  }

  Widget _buildBody(SubscriptionStatusResponse? status) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error == 'creator_required' ||
        (status != null && !status.hasCreator)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Отложенная публикация',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Доступно с тарифом H.A.N. Creator или Pro.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    context.push(SubscriptionRoute.pathWithProduct('creator')),
                child: const Text('Выбрать тариф'),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить',
        subtitle: _error,
        action: FilledButton(
          onPressed: _load,
          child: const Text('Повторить'),
        ),
      );
    }

    if (_posts.isEmpty) {
      return const AppEmptyState(
        icon: Icons.schedule_rounded,
        title: 'Нет запланированных постов',
        subtitle: 'При создании поста выберите «Время публикации»',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final post = _posts[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(_iconForType(post.type)),
              ),
              title: Text(
                post.title?.isNotEmpty == true
                    ? post.title!
                    : 'Пост #${post.id}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_formatDate(post.scheduledPublishAt)}\n'
                '${post.type}${post.channelId != null ? ' · канал #${post.channelId}' : ''}',
              ),
              isThreeLine: true,
              onTap: () => _reschedule(post),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_calendar),
                    tooltip: 'Изменить время',
                    onPressed: () => _reschedule(post),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Отменить',
                    onPressed: () => _cancel(post),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'photo':
        return Icons.image_outlined;
      case 'reel':
        return Icons.videocam_outlined;
      case 'recipe':
        return Icons.restaurant_menu_outlined;
      default:
        return Icons.article_outlined;
    }
  }
}
