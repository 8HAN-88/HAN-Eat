import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/subscription_service.dart';
import '../../../widgets/app_empty_state.dart';

/// Продвигаемые посты (Creator / Pro), до 5 одновременно.
class PromotedPostsScreen extends StatefulWidget {
  const PromotedPostsScreen({super.key});

  @override
  State<PromotedPostsScreen> createState() => _PromotedPostsScreenState();
}

class _PromotedPostsScreenState extends State<PromotedPostsScreen> {
  bool _loading = true;
  String? _error;
  List<PromotedPostSummary> _posts = [];
  int _limit = 5;

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
      final posts = await ChannelService.getPromotedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _limit = stats.promotedLimit;
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

  Future<void> _unpromote(PromotedPostSummary post) async {
    try {
      await ChannelService.unpromotePost(post.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Продвижение снято')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Продвижение'),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Продвижение постов доступно с тарифом Creator или Pro.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
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
        icon: Icons.trending_up_rounded,
        title: 'Нет активных продвижений',
        subtitle:
            'Откройте пост в канале → «⋯» → «Продвинуть в ленте»',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '$_limit слотов · занято ${_posts.length}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        ..._posts.map((p) {
          final title = (p.title?.trim().isNotEmpty == true)
              ? p.title!
              : 'Пост #${p.id}';
          return Card(
            child: ListTile(
              leading: const Icon(Icons.trending_up, color: Colors.amber),
              title: Text(title),
              subtitle: Text(p.type),
              trailing: IconButton(
                tooltip: 'Снять продвижение',
                icon: const Icon(Icons.close),
                onPressed: () => _unpromote(p),
              ),
            ),
          );
        }),
      ],
    );
  }
}
