import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

/// Дашборд продуктовой аналитики AI-плана питания.
class MealPlanAnalyticsScreen extends StatefulWidget {
  const MealPlanAnalyticsScreen({super.key});

  @override
  State<MealPlanAnalyticsScreen> createState() => _MealPlanAnalyticsScreenState();
}

class _MealPlanAnalyticsScreenState extends State<MealPlanAnalyticsScreen> {
  int _days = 30;
  bool _loading = true;
  Map<String, dynamic>? _data;
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
      final token = await AuthService.getAccessTokenForApi();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Войдите в аккаунт для просмотра аналитики';
          _loading = false;
        });
        return;
      }
      final data = await ApiService.getMealPlanAnalytics(days: _days);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить аналитику');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
  final bottom = floatingBottomPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика плана питания'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _days,
            onSelected: (d) {
              setState(() => _days = d);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('7 дней')),
              PopupMenuItem(value: 30, child: Text('30 дней')),
              PopupMenuItem(value: 90, child: Text('90 дней')),
            ],
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: _error!.contains('Войдите')
                      ? Icons.login_rounded
                      : Icons.cloud_off_rounded,
                  title: _error!.contains('Войдите')
                      ? 'Нужен вход'
                      : 'Не удалось загрузить',
                  subtitle: _error,
                  action: _error!.contains('Войдите')
                      ? FilledButton(
                          onPressed: () => context.push(LoginRoute.path),
                          child: const Text('Войти'),
                        )
                      : FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
                  children: [
                    Text(
                      'За последние $_days дн.',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    _metricCard(
                      theme,
                      'Сгенерировано планов',
                      _data!['plans_generated'],
                      Icons.auto_awesome_outlined,
                    ),
                    _metricCard(
                      theme,
                      'Регенерации',
                      _data!['regenerations'],
                      Icons.refresh,
                    ),
                    _metricCard(
                      theme,
                      'Списки покупок',
                      _data!['shopping_list_uses'],
                      Icons.shopping_cart_outlined,
                    ),
                    _metricCard(
                      theme,
                      'Открытия рецептов',
                      _data!['recipe_opens'],
                      Icons.menu_book_outlined,
                    ),
                    _metricCard(
                      theme,
                      'Добавлено в календарь',
                      _data!['calendar_applies'],
                      Icons.calendar_month_outlined,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.timeline_outlined),
                        title: const Text('Средняя длительность плана'),
                        trailing: Text(
                          '${_data!['average_plan_duration_days'] ?? 0} дн.',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (_data!['retention_hint'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Вы активно пользуетесь AI-планом — отличная вовлечённость.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _metricCard(
    ThemeData theme,
    String label,
    dynamic value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label),
        trailing: Text(
          '${value ?? 0}',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
