// Экран аналитики для авторов
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../services/analytics_service.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  final int? postId; // Если указан, показываем аналитику поста, иначе профиля
  
  const AnalyticsScreen({super.key, this.postId});
  
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _selectedDays = 30;
  bool _isLoading = false;
  PostAnalyticsResponse? _postAnalytics;
  ProfileAnalyticsResponse? _profileAnalytics;
  
  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }
  
  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    
    try {
      if (widget.postId != null) {
        final analytics = await AnalyticsService.getPostAnalytics(
          postId: widget.postId!,
          days: _selectedDays,
        );
        setState(() => _postAnalytics = analytics);
      } else {
        final analytics = await AnalyticsService.getProfileAnalytics(
          days: _selectedDays,
        );
        setState(() => _profileAnalytics = analytics);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки аналитики: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.postId != null ? 'Аналитика поста' : 'Аналитика профиля'),
        actions: [
          // Селектор периода
          PopupMenuButton<int>(
            initialValue: _selectedDays,
            onSelected: (days) {
              setState(() => _selectedDays = days);
              _loadAnalytics();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 7, child: Text('7 дней')),
              const PopupMenuItem(value: 30, child: Text('30 дней')),
              const PopupMenuItem(value: 90, child: Text('90 дней')),
              const PopupMenuItem(value: 180, child: Text('180 дней')),
              const PopupMenuItem(value: 365, child: Text('Год')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_selectedDays} дн'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.postId != null
              ? _buildPostAnalytics()
              : _buildProfileAnalytics(),
    );
  }
  
  Widget _buildPostAnalytics() {
    if (_postAnalytics == null) {
      return const Center(child: Text('Нет данных'));
    }
    
    final analytics = _postAnalytics!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Основные метрики
          _buildMetricsCard(
            title: 'Основные метрики',
            metrics: [
              _MetricItem(
                label: 'Просмотры',
                value: '${analytics.viewsTotal}',
                subtitle: '${analytics.viewsUnique} уникальных',
                icon: Icons.visibility,
                color: Colors.blue,
              ),
              _MetricItem(
                label: 'Лайки',
                value: '${analytics.likesCount}',
                icon: Icons.favorite,
                color: Colors.red,
              ),
              _MetricItem(
                label: 'Комментарии',
                value: '${analytics.commentsCount}',
                icon: Icons.comment,
                color: Colors.orange,
              ),
              _MetricItem(
                label: 'Сохранения',
                value: '${analytics.savesCount}',
                icon: Icons.bookmark,
                color: Colors.purple,
              ),
              _MetricItem(
                label: 'Репосты',
                value: '${analytics.repostsCount}',
                icon: Icons.repeat,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Метрики вовлеченности
          _buildMetricsCard(
            title: 'Вовлеченность',
            metrics: [
              _MetricItem(
                label: 'CTR',
                value: '${(analytics.ctr * 100).toStringAsFixed(2)}%',
                subtitle: 'Click-Through Rate',
                icon: Icons.touch_app,
                color: Colors.teal,
              ),
              _MetricItem(
                label: 'Engagement Rate',
                value: '${(analytics.engagementRate * 100).toStringAsFixed(2)}%',
                subtitle: 'Уровень вовлеченности',
                icon: Icons.trending_up,
                color: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // График просмотров
          if (analytics.viewsByDay.isNotEmpty) ...[
            _buildChartCard(
              title: 'Просмотры по дням',
              data: analytics.viewsByDay,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
  
  Widget _buildProfileAnalytics() {
    if (_profileAnalytics == null) {
      return const Center(child: Text('Нет данных'));
    }
    
    final analytics = _profileAnalytics!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Общая статистика
          _buildMetricsCard(
            title: 'Общая статистика',
            metrics: [
              _MetricItem(
                label: 'Посты',
                value: '${analytics.postsCount}',
                icon: Icons.article,
                color: Colors.blue,
              ),
              _MetricItem(
                label: 'Каналы',
                value: '${analytics.channelsCount}',
                icon: Icons.cable,
                color: Colors.orange,
              ),
              _MetricItem(
                label: 'Подписчики',
                value: '${analytics.followersCount}',
                icon: Icons.people,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Метрики контента
          _buildMetricsCard(
            title: 'Метрики контента',
            metrics: [
              _MetricItem(
                label: 'Просмотры',
                value: '${analytics.totalViews}',
                icon: Icons.visibility,
                color: Colors.blue,
              ),
              _MetricItem(
                label: 'Лайки',
                value: '${analytics.totalLikes}',
                icon: Icons.favorite,
                color: Colors.red,
              ),
              _MetricItem(
                label: 'Комментарии',
                value: '${analytics.totalComments}',
                icon: Icons.comment,
                color: Colors.orange,
              ),
              _MetricItem(
                label: 'Сохранения',
                value: '${analytics.totalSaves}',
                icon: Icons.bookmark,
                color: Colors.purple,
              ),
              _MetricItem(
                label: 'Репосты',
                value: '${analytics.totalReposts}',
                icon: Icons.repeat,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Средняя вовлеченность
          _buildMetricsCard(
            title: 'Вовлеченность',
            metrics: [
              _MetricItem(
                label: 'Средний Engagement Rate',
                value: '${(analytics.avgEngagementRate * 100).toStringAsFixed(2)}%',
                subtitle: 'Средний уровень вовлеченности',
                icon: Icons.trending_up,
                color: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // График просмотров
          if (analytics.viewsByDay.isNotEmpty) ...[
            _buildChartCard(
              title: 'Просмотры по дням',
              data: analytics.viewsByDay,
            ),
            const SizedBox(height: 16),
          ],
          // Топ посты
          if (analytics.topPosts.isNotEmpty) ...[
            _buildTopPostsCard(analytics.topPosts),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
  
  Widget _buildMetricsCard({
    required String title,
    required List<_MetricItem> metrics,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...metrics.map((metric) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: metric.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(metric.icon, color: metric.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (metric.subtitle != null)
                          Text(
                            metric.subtitle!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    metric.value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
  
  Widget _buildChartCard({
    required String title,
    required List<DailyCount> data,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _SimpleLineChart(data: data),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTopPostsCard(List<PostAnalyticsResponse> topPosts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Топ посты',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...topPosts.asMap().entries.map((entry) {
              final index = entry.key;
              final post = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Пост #${post.postId}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${post.viewsTotal} просмотров • ${(post.engagementRate * 100).toStringAsFixed(1)}% engagement',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  
  _MetricItem({
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _SimpleLineChart extends StatelessWidget {
  final List<DailyCount> data;
  
  const _SimpleLineChart({required this.data});
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('Нет данных'));
    }
    
    final maxValue = data.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    final minValue = 0;
    final range = maxValue - minValue;
    
    return CustomPaint(
      painter: _ChartPainter(data: data, maxValue: maxValue, range: range),
      child: Container(),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<DailyCount> data;
  final int maxValue;
  final int range;
  
  _ChartPainter({
    required this.data,
    required this.maxValue,
    required this.range,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final fillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final fillPath = Path();
    
    final stepX = size.width / (data.length - 1);
    final padding = 40.0;
    final chartHeight = size.height - padding * 2;
    
    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = range > 0 ? (data[i].count - 0) / range : 0.0;
      final y = size.height - padding - (normalizedValue * chartHeight);
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - padding);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    
    fillPath.lineTo(size.width, size.height - padding);
    fillPath.close();
    
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
    
    // Точки
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    
    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = range > 0 ? (data[i].count - 0) / range : 0.0;
      final y = size.height - padding - (normalizedValue * chartHeight);
      
      canvas.drawCircle(Offset(x, y), 4, pointPaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

