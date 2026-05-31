import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../meal_plan/presentation/meal_plan_nutrition_settings_screen.dart';
import '../../../services/notification_service.dart';
import '../../../services/auth_service.dart';
import '../../../app/theme_mode_controller.dart';
import '../application/analysis_mode_controller.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../widgets/ai_scan_credits_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _unreadNotificationsCount = 0;
  bool _isAdminOrModerator = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _checkAdminStatus();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) {
        setState(() => _unreadNotificationsCount = count);
      }
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  Future<void> _checkAdminStatus() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (mounted && user != null) {
        setState(() {
          _isAdmin = user.isAdmin;
          _isAdminOrModerator = user.isAdmin || user.isModerator;
        });
      }
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'H.A.N. Eat',
      applicationVersion: '1.0.0',
      applicationLegalese: '© H.A.N. Eat. Рецепты, план питания и сообщество.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(analysisSettingsProvider);
    final controller = ref.read(analysisSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final serviceItems = <_SettingsItem>[
      _SettingsItem(
        title: 'Настройки профиля',
        icon: Icons.manage_accounts_outlined,
        subtitle: 'Имя, аватар, аналитика, выход из аккаунта',
        onTap: () => context.push(ProfileAuthRoute.path),
      ),
      _SettingsItem(
        title: 'Пароль и email',
        icon: Icons.lock_outline,
        subtitle: 'Смена пароля, смена email',
        onTap: () => context.push(AccountSecurityRoute.path),
      ),
      _SettingsItem(
        title: 'Уведомления',
        icon: Icons.notifications_outlined,
        subtitle: 'Тренды, новые видео сообщества, напоминания',
        onTap: () {
          context.push(NotificationsRoute.path);
          _loadUnreadCount();
        },
        badge: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null,
      ),
      _SettingsItem(
        title: 'Поддержка',
        icon: Icons.support_agent_outlined,
        subtitle: 'Создать обращение, отменить подписку',
        onTap: () => context.push('/support'),
      ),
      _SettingsItem(
        title: 'Подписка',
        icon: Icons.workspace_premium_outlined,
        subtitle: 'Тарифы AI, Creator и Pro — от 199 ₽/мес',
        onTap: () => context.push('/subscription'),
      ),
      _SettingsItem(
        title: 'Настройки питания',
        icon: Icons.monitor_heart_outlined,
        subtitle: 'Цель, калории, повторы — для AI-плана',
        onTap: () => context.push(MealPlanNutritionSettingsRoute.path),
      ),
      _SettingsItem(
        title: 'Поддержка и безопасность',
        icon: Icons.verified_user_outlined,
        subtitle: 'GDPR, модерация, жалобы, правила сообщества',
        onTap: () => context.push('/support-security'),
      ),
      _SettingsItem(
        title: 'Резервная копия',
        icon: Icons.backup_outlined,
        subtitle: 'Экспорт и восстановление данных',
        onTap: () => context.push('/backup'),
      ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Возвраты подписок',
          icon: Icons.currency_exchange_outlined,
          subtitle: 'Очередь запросов на возврат (ЮKassa)',
          onTap: () => context.push(AdminRefundQueueRoute.path),
        ),
      if (_isAdminOrModerator)
        _SettingsItem(
          title: 'Модерация',
          icon: Icons.admin_panel_settings_outlined,
          subtitle: 'Панель модератора и очередь контента',
          onTap: () => context.push(ModerationDashboardRoute.path),
          badge: null,
        ),
      _SettingsItem(
        title: 'О приложении',
        icon: Icons.info_outline_rounded,
        subtitle: 'Версия, условия использования, конфиденциальность',
        onTap: () => _showAboutDialog(context),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          20 + floatingBottomPadding(context),
        ),
        children: [
          _SettingsSectionHeader(title: 'Внешний вид'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Тема',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _ThemeModeRow(
                    selected: ref.watch(themeModeProvider),
                    onSelected: (mode) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Язык перевода',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        supportedLanguages.keys.contains(settings.language)
                            ? settings.language
                            : 'ru',
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.language),
                    ),
                    items: [
                      for (final entry in supportedLanguages.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.changeLanguage(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Все рецепты, ингредиенты и шаги будут автоматически переводиться на выбранный язык.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SettingsSectionHeader(title: 'Аккаунт и сервисы'),
          const Card(
            child: AiScanCreditsTile(),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < serviceItems.length; i++) ...[
                  _SettingsTile(item: serviceItems[i]),
                  if (i < serviceItems.length - 1)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: scheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Переключатель темы: три варианта в одну строку, подпись без переноса.
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({
    required this.selected,
    required this.onSelected,
  });

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  static const _options = [
    _ThemeModeChoice(ThemeMode.system, Icons.brightness_auto, 'Системная'),
    _ThemeModeChoice(ThemeMode.light, Icons.light_mode, 'Светлая'),
    _ThemeModeChoice(ThemeMode.dark, Icons.dark_mode, 'Тёмная'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ThemeModeOption(
              icon: _options[i].icon,
              label: _options[i].label,
              isSelected: selected == _options[i].mode,
              onTap: () => onSelected(_options[i].mode),
              scheme: scheme,
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeModeChoice {
  const _ThemeModeChoice(this.mode, this.icon, this.label);

  final ThemeMode mode;
  final IconData icon;
  final String label;
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.65)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? scheme.primary : Colors.transparent,
              width: isSelected ? 1.5 : 0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.item});

  final _SettingsItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minLeadingWidth: 40,
      leading: Icon(
        item.icon,
        color: scheme.primary,
      ),
      title: Row(
        children: [
          Expanded(child: Text(item.title)),
          if (item.badge != null && item.badge! > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Badge(
                label: Text(
                  item.badge! > 99 ? '99+' : '${item.badge}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          item.subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
      onTap: item.onTap,
    );
  }
}

class _SettingsItem {
  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final int? badge;
}
