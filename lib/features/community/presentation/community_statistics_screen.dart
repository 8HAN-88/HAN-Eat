import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import '../../../models/community.dart';
import '../../../services/statistics_service.dart';
import '../../../services/community_management_service.dart';
import '../../../widgets/app_empty_state.dart';

/// Экран статистики канала
class CommunityStatisticsScreen extends StatefulWidget {
  final String communityId;

  const CommunityStatisticsScreen({
    super.key,
    required this.communityId,
  });

  @override
  State<CommunityStatisticsScreen> createState() =>
      _CommunityStatisticsScreenState();
}

class _CommunityStatisticsScreenState extends State<CommunityStatisticsScreen> {
  CommunityStatistics? _statistics;
  Community? _community;
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final community =
          await CommunityManagementService.getCommunity(widget.communityId);
      final statistics =
          await StatisticsService.getCommunityStatistics(widget.communityId);
      if (!mounted) return;
      setState(() {
        _community = community;
        _statistics = statistics;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика канала'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить статистику',
        subtitle: userVisibleError(
          _loadError!,
          fallback: 'Проверьте сеть и попробуйте снова',
        ),
        action: FilledButton(
          onPressed: _loadData,
          child: const Text('Повторить'),
        ),
      );
    }
    if (_statistics == null) {
      return const AppEmptyState(
        icon: Icons.insights_outlined,
        title: 'Пока нет данных',
        subtitle: 'Статистика появится после публикаций в канале',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _community?.name ?? 'Канал',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Участники', '${_statistics!.membersCount}'),
                    _buildStatItem('Посты', '${_statistics!.postsCount}'),
                    _buildStatItem('Просмотры', '${_statistics!.totalViews}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вовлечённость',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Лайки: ${_statistics!.totalLikes}'),
                Text('Комментарии: ${_statistics!.totalComments}'),
                Text(
                  'Средняя вовлечённость: ${_statistics!.averageEngagement.toStringAsFixed(2)}%',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'По типам постов',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_statistics!.postsByType.isEmpty)
                  Text(
                    'Нет постов для анализа',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ..._statistics!.postsByType.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key),
                          Text('${entry.value}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_statistics!.topPosts.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Топ посты',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ..._statistics!.topPosts.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Пост ${entry.key + 1}'),
                              Text(
                                'Вовлечённость: ${entry.value.engagementRate.toStringAsFixed(2)}%',
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(label),
      ],
    );
  }
}
