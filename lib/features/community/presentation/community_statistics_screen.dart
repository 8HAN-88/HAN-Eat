import 'package:flutter/material.dart';
import '../../../models/community.dart';
import '../../../services/statistics_service.dart';
import '../../../services/community_management_service.dart';

/// Экран статистики канала
class CommunityStatisticsScreen extends StatefulWidget {
  final String communityId;

  const CommunityStatisticsScreen({
    super.key,
    required this.communityId,
  });

  @override
  State<CommunityStatisticsScreen> createState() => _CommunityStatisticsScreenState();
}

class _CommunityStatisticsScreenState extends State<CommunityStatisticsScreen> {
  CommunityStatistics? _statistics;
  Community? _community;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final community = await CommunityManagementService.getCommunity(widget.communityId);
      final statistics = await StatisticsService.getCommunityStatistics(widget.communityId);
      setState(() {
        _community = community;
        _statistics = statistics;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика канала'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _statistics == null
              ? const Center(child: Text('Нет данных'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Основные метрики
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

                    // Вовлечённость
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

                    // По типам постов
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

                    // Топ посты
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
                ),
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

