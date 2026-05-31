import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

/// Инструменты автора: лимиты продвижения, запланированные посты.
class CreatorToolsScreen extends StatefulWidget {
  const CreatorToolsScreen({super.key});

  @override
  State<CreatorToolsScreen> createState() => _CreatorToolsScreenState();
}

class _CreatorToolsScreenState extends State<CreatorToolsScreen> {
  bool _loading = true;
  CreatorStats? _stats;
  String? _error;

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
      final stats = await ChannelService.getCreatorStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инструменты автора'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error == 'creator_required') {
      return _upsell();
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

    final stats = _stats!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: InkWell(
            onTap: () => context.push(PromotedPostsRoute.path),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Продвижение в ленте',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: stats.promotedLimit > 0
                        ? stats.promotedCount / stats.promotedLimit
                        : 0,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${stats.promotedCount} из ${stats.promotedLimit} активных',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Управление продвижениями · «⋯» на посте в канале',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Запланированные посты'),
            subtitle: Text(
              stats.scheduledCount > 0
                  ? '${stats.scheduledCount} ожидают публикации'
                  : 'Отложенная публикация в каналах',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(ScheduledPostsRoute.path),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('Аналитика'),
            subtitle: const Text('Статистика постов и канала'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed('analytics'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Подписка'),
            subtitle: const Text('Creator или Pro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(SubscriptionRoute.pathWithProduct('creator')),
          ),
        ),
      ],
    );
  }

  Widget _upsell() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Инструменты автора',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Продвижение, отложенные посты и аналитика — с тарифом H.A.N. Creator или Pro.',
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
}
