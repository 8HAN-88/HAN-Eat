import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/notification_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/subscription_status_cache.dart';
import '../../../services/user_service.dart';
import '../../../services/web_app_update_service.dart';
import '../../../services/chat_thread_ui_prefs.dart';
import '../../../utils/api_error_parser.dart';
import '../../../app/theme_mode_controller.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../../widgets/telegram_ui.dart';
import '../../subscription/creator_upsell.dart';
import '../application/last_seen_privacy.dart';
import '../application/voice_privacy.dart';
import 'blocked_users_screen.dart';
import 'paid_message_exceptions_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _unreadNotificationsCount = 0;
  bool _isAdminOrModerator = false;
  bool _isAdmin = false;
  bool _slowModeCountdownHapticsEnabled = true;
  bool _autoRetryOnLimitsEnabled = true;
  String _lastSeenPrivacy = lastSeenPrivacyEverybody;
  String _voicePrivacy = voicePrivacyEverybody;
  bool _archiveNonContacts = false;
  bool _showReadReceipts = true;
  int _paidMessageStars = 0;
  bool _privacyBusy = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _checkAdminStatus();
    _loadChatUiPrefs();
    _loadPrivacyPrefs();
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

  Future<void> _loadChatUiPrefs() async {
    try {
      final hapticsEnabled =
          await ChatThreadUiPrefs.isSlowModeCountdownHapticsEnabled();
      final autoRetryEnabled =
          await ChatThreadUiPrefs.isAutoRetryOnLimitsEnabled();
      if (!mounted) return;
      setState(() {
        _slowModeCountdownHapticsEnabled = hapticsEnabled;
        _autoRetryOnLimitsEnabled = autoRetryEnabled;
      });
    } catch (_) {}
  }

  Future<void> _toggleSlowModeCountdownHaptics(bool enabled) async {
    setState(() => _slowModeCountdownHapticsEnabled = enabled);
    try {
      await ChatThreadUiPrefs.setSlowModeCountdownHapticsEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _slowModeCountdownHapticsEnabled = !enabled);
    }
  }

  Future<void> _toggleAutoRetryOnLimits(bool enabled) async {
    setState(() => _autoRetryOnLimitsEnabled = enabled);
    try {
      await ChatThreadUiPrefs.setAutoRetryOnLimitsEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoRetryOnLimitsEnabled = !enabled);
    }
  }

  Future<void> _loadPrivacyPrefs() async {
    try {
      final user =
          AuthService.instance.currentUser ?? await AuthService.getCurrentUser();
      if (!mounted || user == null) return;
      setState(() {
        _lastSeenPrivacy = normalizeLastSeenPrivacy(
          user.lastSeenPrivacy,
          showLastSeen: user.showLastSeen,
        );
        _voicePrivacy = normalizeVoicePrivacy(user.voicePrivacy);
        _archiveNonContacts = user.archiveNonContacts;
        _showReadReceipts = user.showReadReceipts;
        _paidMessageStars = user.paidMessageStars;
      });
    } catch (_) {}
  }

  Future<void> _editPaidMessageStars() async {
    if (_privacyBusy) return;
    final next = await pickPaidMessageStars(
      context,
      current: _paidMessageStars,
    );
    if (next == null || !mounted) return;
    setState(() {
      _paidMessageStars = next;
      _privacyBusy = true;
    });
    try {
      final updated =
          await UserService.updateProfile(paidMessageStars: next);
      await AuthService.persistUpdatedUser(updated);
      if (!mounted) return;
      setState(() {
        _paidMessageStars = updated.paidMessageStars;
        _privacyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _privacyBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      await _loadPrivacyPrefs();
    }
  }

  Future<void> _pickLastSeenPrivacy() async {
    if (_privacyBusy) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Кто видит время в сети',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final value in lastSeenPrivacyValues)
                ListTile(
                  title: Text(lastSeenPrivacyLabel(value)),
                  subtitle: Text(
                    switch (value) {
                      lastSeenPrivacyContacts =>
                        'Только люди из ваших контактов. У кого уровень выше — всё равно видят вас',
                      lastSeenPrivacyNobody =>
                        SubscriptionStatusCache.peek()
                                    ?.hasFeature('privacy_plus') ==
                                true
                            ? 'Статус скрыт, чужой last seen вам виден. У кого уровень выше — всё равно видят вас'
                            : 'Статус скрыт — чужой last seen тоже не виден. У кого уровень выше — всё равно видят вас',
                      _ => 'Все пользователи HanWe',
                    },
                  ),
                  trailing: _lastSeenPrivacy == value
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, value),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  lastSeenHigherLevelNote,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted || selected == _lastSeenPrivacy) return;
    final previous = _lastSeenPrivacy;
    setState(() {
      _lastSeenPrivacy = selected;
      _privacyBusy = true;
    });
    try {
      final updated =
          await UserService.updateProfile(lastSeenPrivacy: selected);
      await AuthService.persistUpdatedUser(updated);
      if (!mounted) return;
      setState(() {
        _lastSeenPrivacy = normalizeLastSeenPrivacy(
          updated.lastSeenPrivacy,
          showLastSeen: updated.showLastSeen,
        );
        _privacyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastSeenPrivacy = previous;
        _privacyBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _pickVoicePrivacy() async {
    if (_privacyBusy) return;
    if (_voicePrivacy == voicePrivacyEverybody &&
        !hasFlexFeature('voice_privacy')) {
      await showCreatorUpsell(context);
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Кто может присылать голос и кружки',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final value in voicePrivacyValues)
                ListTile(
                  title: Text(voicePrivacyLabel(value)),
                  subtitle: Text(
                    switch (value) {
                      voicePrivacyContacts =>
                        'Только люди из ваших контактов',
                      voicePrivacyNobody =>
                        'Никто не сможет прислать голосовое или кружок',
                      _ => 'Все пользователи HanWe',
                    },
                  ),
                  trailing: _voicePrivacy == value
                      ? const Icon(Icons.check)
                      : (value != voicePrivacyEverybody &&
                              !hasFlexFeature('voice_privacy')
                          ? const Icon(Icons.lock_outline)
                          : null),
                  onTap: () => Navigator.pop(ctx, value),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted || selected == _voicePrivacy) return;
    if (selected != voicePrivacyEverybody &&
        !hasFlexFeature('voice_privacy')) {
      await showCreatorUpsell(context);
      return;
    }
    final previous = _voicePrivacy;
    setState(() {
      _voicePrivacy = selected;
      _privacyBusy = true;
    });
    try {
      final updated =
          await UserService.updateProfile(voicePrivacy: selected);
      await AuthService.persistUpdatedUser(updated);
      if (!mounted) return;
      setState(() {
        _voicePrivacy = normalizeVoicePrivacy(updated.voicePrivacy);
        _privacyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voicePrivacy = previous;
        _privacyBusy = false;
      });
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleArchiveNonContacts(bool enabled) async {
    if (_privacyBusy) return;
    if (enabled && !hasFlexFeature('archive_non_contacts')) {
      await showCreatorUpsell(context);
      return;
    }
    setState(() {
      _archiveNonContacts = enabled;
      _privacyBusy = true;
    });
    try {
      final updated =
          await UserService.updateProfile(archiveNonContacts: enabled);
      await AuthService.persistUpdatedUser(updated);
      if (!mounted) return;
      setState(() {
        _archiveNonContacts = updated.archiveNonContacts;
        _privacyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _archiveNonContacts = !enabled;
        _privacyBusy = false;
      });
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleShowReadReceipts(bool enabled) async {
    if (_privacyBusy) return;
    setState(() {
      _showReadReceipts = enabled;
      _privacyBusy = true;
    });
    try {
      final updated =
          await UserService.updateProfile(showReadReceipts: enabled);
      await AuthService.persistUpdatedUser(updated);
      if (!mounted) return;
      setState(() {
        _showReadReceipts = updated.showReadReceipts;
        _privacyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showReadReceipts = !enabled;
        _privacyBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'HanWe',
      applicationVersion: kIsWeb && WebAppUpdateService.embeddedBuild.isNotEmpty
          ? '1.0.0 (${WebAppUpdateService.embeddedBuild})'
          : '1.0.0',
      applicationLegalese: '© HanWe. Чаты, лента, каналы и общение.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final serviceItems = <_SettingsItem>[
      _SettingsItem(
        title: 'Настройки профиля',
        icon: Icons.manage_accounts_outlined,
        subtitle: 'Имя, аватар, email, телефон, пароль',
        onTap: () => context.push(ProfileAuthRoute.path),
      ),
      _SettingsItem(
        title: 'Аккаунт и безопасность',
        icon: Icons.security_outlined,
        subtitle: 'Сессия, пароль, выход со всех устройств',
        onTap: () => context.push(AccountSecurityRoute.path),
      ),
      _SettingsItem(
        title: 'Входящие',
        icon: Icons.inbox_outlined,
        subtitle: 'Лайки, комментарии, сообщения и другие события',
        onTap: () {
          context.push(NotificationsRoute.path);
          _loadUnreadCount();
        },
        badge: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null,
      ),
      _SettingsItem(
        title: 'Настройки уведомлений',
        icon: Icons.notifications_outlined,
        subtitle: 'Push, типы событий, регистрация устройства',
        onTap: () => context.push(NotificationSettingsRoute.path),
      ),
      _SettingsItem(
        title: 'Поддержка',
        icon: Icons.support_agent_outlined,
        subtitle: 'Создать обращение, отменить подписку',
        onTap: () => context.push(SupportContactRoute.path),
      ),
      _SettingsItem(
        title: 'Моя подписка',
        icon: Icons.tune_rounded,
        subtitle: 'Соберите набор функций — от 39 ₽/мес',
        onTap: () => context.push(FlexSubscriptionRoute.path),
      ),
      _SettingsItem(
        title: 'Звёзды и кошелёк',
        icon: Icons.stars_rounded,
        subtitle: 'Баланс, донаты, покупки контента и бусты',
        onTap: () => context.push(StarsWalletRoute.path),
      ),
      _SettingsItem(
        title: 'Мои боты',
        icon: Icons.smart_toy_outlined,
        subtitle: 'Создание ботов, команды и подключение к чатам',
        onTap: () => context.push(MyBotsRoute.path),
      ),
      _SettingsItem(
        title: 'Поддержка и безопасность',
        icon: Icons.verified_user_outlined,
        subtitle: 'GDPR, модерация, жалобы, правила сообщества',
        onTap: () => context.push(SupportSecurityRoute.path),
      ),
      _SettingsItem(
        title: 'Чёрный список',
        icon: Icons.block_outlined,
        subtitle: 'Заблокированные пользователи',
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
          );
        },
      ),
      _SettingsItem(
        title: 'Резервная копия',
        icon: Icons.backup_outlined,
        subtitle: 'Экспорт и восстановление данных',
        onTap: () => context.push(BackupRoute.path),
      ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Возвраты подписок',
          icon: Icons.currency_exchange_outlined,
          subtitle: 'Очередь запросов на возврат (ЮKassa)',
          onTap: () => context.push(AdminRefundQueueRoute.path),
        ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Функции подписки',
          icon: Icons.extension_outlined,
          subtitle: 'Каталог уровней, блоки и типы функций',
          onTap: () => context.push(AdminFlexFeaturesRoute.path),
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
      body: AppGradientBackground(
        child: ListView(
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
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                secondary: const Icon(Icons.vibration_outlined),
                title: const Text('Вибро-отсчёт slow mode'),
                subtitle: const Text(
                  'Лёгкий тактильный акцент на 3-2-1 и при разблокировке отправки',
                ),
                value: _slowModeCountdownHapticsEnabled,
                onChanged: _toggleSlowModeCountdownHaptics,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                secondary: const Icon(Icons.autorenew_rounded),
                title: const Text('Автоповтор при лимитах'),
                subtitle: const Text(
                  'Автоматически повторять отправку после slow mode и антифлуда',
                ),
                value: _autoRetryOnLimitsEnabled,
                onChanged: _toggleAutoRetryOnLimits,
              ),
            ),
            const SizedBox(height: 24),
            _SettingsSectionHeader(title: 'Приватность'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Время в сети'),
                    subtitle: Text(
                      '${lastSeenPrivacyLabel(_lastSeenPrivacy)}\n'
                      '$lastSeenHigherLevelNote',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _privacyBusy ? null : _pickLastSeenPrivacy,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.mic_off_outlined),
                    title: const Text('Голосовые сообщения'),
                    subtitle: Text(
                      '${voicePrivacyLabel(_voicePrivacy)}\n'
                      'Кто может присылать голос и кружки',
                    ),
                    isThreeLine: true,
                    trailing: hasFlexFeature('voice_privacy')
                        ? const Icon(Icons.chevron_right_rounded)
                        : const Icon(Icons.lock_outline),
                    onTap: _privacyBusy ? null : _pickVoicePrivacy,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: hasFlexFeature('archive_non_contacts')
                        ? const Icon(Icons.inventory_2_outlined)
                        : const Icon(Icons.lock_outline),
                    title: const Text('Архив незнакомцев'),
                    subtitle: const Text(
                      'Новые чаты не из контактов сразу в архив и без звука',
                    ),
                    value: _archiveNonContacts,
                    onChanged:
                        _privacyBusy ? null : _toggleArchiveNonContacts,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.done_all_outlined),
                    title: const Text('Отчёты о прочтении'),
                    subtitle: const Text(
                      'Синие галочки. Если выключить — взаимно скрываются',
                    ),
                    value: _showReadReceipts,
                    onChanged: _privacyBusy ? null : _toggleShowReadReceipts,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.stars_rounded),
                    title: const Text('Плата за сообщения'),
                    subtitle: Text(
                      _paidMessageStars > 0
                          ? '$_paidMessageStars ★ за каждое входящее ЛС'
                          : 'Выключено — писать вам можно бесплатно',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _privacyBusy ? null : _editPaidMessageStars,
                  ),
                  if (_paidMessageStars > 0) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Кто пишет бесплатно'),
                      subtitle: const Text(
                        'Исключения — как в Telegram Paid Messages',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const PaidMessageExceptionsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SettingsSectionHeader(title: 'Аккаунт и сервисы'),
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
    return TelegramSectionHeader(
      title: title,
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
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
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: scheme.primary.withValues(alpha: 0.13),
        child: Icon(
          item.icon,
          size: 20,
          color: scheme.primary,
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(item.title)),
          if (item.badge != null && item.badge! > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TelegramUnreadBadge(count: item.badge!),
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
