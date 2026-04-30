import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/notification_service.dart';
import '../../../services/auth_service.dart';
import '../../../app/theme_mode_controller.dart';
import '../application/analysis_mode_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _unreadNotificationsCount = 0;
  bool _isAdminOrModerator = false;
  
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

    final placeholderItems = [
      _SettingsItem(
        title: 'Профиль',
        icon: Icons.person_outline_rounded,
        subtitle: 'Войти, загрузить аватар, управлять UGC',
        onTap: () => context.push('/profile'),
      ),
      _SettingsItem(
        title: 'Уведомления',
        icon: Icons.notifications_outlined,
        subtitle: 'Тренды, новые видео сообщества, напоминания',
        onTap: () {
          context.push('/notifications-list');
          // Обновляем счетчик после перехода
          _loadUnreadCount();
        },
        badge: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null,
      ),
      _SettingsItem(
        title: 'Поддержка',
        icon: Icons.support_agent,
        subtitle: 'Создать обращение, отменить подписку',
        onTap: () => context.push('/support'),
      ),
      _SettingsItem(
        title: 'Подписка H.A.N. Plus',
        icon: Icons.workspace_premium_outlined,
        subtitle: 'Без рекламы, оффлайн, анализ питания, выплаты авторам',
        onTap: () => context.push('/subscription'),
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
      // Показывать только для админов/модераторов
      if (_isAdminOrModerator)
        _SettingsItem(
          title: 'Модерация',
          icon: Icons.admin_panel_settings_outlined,
          subtitle: 'Очередь модерации контента',
          onTap: () => context.push('/moderation'),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
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
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('Системная'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Светлая'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Тёмная'),
                      ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (selection) {
                      ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
                    },
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
                    'Язык перевода',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value:
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...placeholderItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  item.icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                onTap: item.onTap,
              ),
            ),
          ),
        ],
      ),
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
