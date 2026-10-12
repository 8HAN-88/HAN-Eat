import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_router.dart';
import '../../../core/config/legal_urls.dart';
import '../../../services/notification_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';
import '../../../services/web_app_update_service.dart';
import '../../../services/chat_thread_ui_prefs.dart';
import '../../../utils/api_error_parser.dart';
import '../../../app/theme_mode_controller.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../../widgets/telegram_ui.dart';
import '../application/last_seen_privacy.dart';

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
      final user = AuthService.instance.currentUser ??
          await AuthService.getCurrentUser();
      if (!mounted || user == null) return;
      setState(() {
        _lastSeenPrivacy = normalizeLastSeenPrivacy(
          user.lastSeenPrivacy,
          showLastSeen: user.showLastSeen,
        );
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
    await _applyPaidMessageStars(next);
  }

  Future<void> _applyPaidMessageStars(int next) async {
    setState(() {
      _paidMessageStars = next;
      _privacyBusy = true;
    });
    try {
      final updated = await UserService.updateProfile(paidMessageStars: next);
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
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_applyPaidMessageStars(next)),
          ),
        ),
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
                  title: Text(
                    lastSeenPrivacyLabel(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    switch (value) {
                      lastSeenPrivacyContacts =>
                        'Только люди из ваших контактов',
                      lastSeenPrivacyNobody =>
                        'Статус «в сети» и время посещения скрыты',
                      _ => 'Все пользователи HanWe',
                    },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _lastSeenPrivacy == value
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted || selected == _lastSeenPrivacy) return;
    await _applyLastSeenPrivacy(selected);
  }

  Future<void> _applyLastSeenPrivacy(String selected) async {
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
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_applyLastSeenPrivacy(selected)),
          ),
        ),
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
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_toggleShowReadReceipts(enabled)),
          ),
        ),
      );
    }
  }

  Future<void> _openLegal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Не удалось открыть: $url'),
        action: SnackBarAction(
          label: 'Скопировать',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
          },
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'HanWe',
      applicationVersion: kIsWeb && WebAppUpdateService.embeddedBuild.isNotEmpty
          ? '1.0.0 (${WebAppUpdateService.embeddedBuild})'
          : '1.0.0',
      applicationLegalese: '© HanWe. Чаты, лента, каналы и общение.',
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                unawaited(_openLegal(context, LegalUrls.termsOfService)),
            child: const Text('Условия использования'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                unawaited(_openLegal(context, LegalUrls.privacyPolicy)),
            child: const Text('Конфиденциальность'),
          ),
        ),
      ],
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
        subtitle: 'Сессии, 2FA, пароль, выход со всех устройств',
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
        title: 'Подписка',
        icon: Icons.workspace_premium_outlined,
        subtitle: 'Одна подписка — от 39 ₽/мес, возможности можно переставить',
        onTap: () => context.push(FlexSubscriptionRoute.path),
      ),
      _SettingsItem(
        title: 'Реферальная программа',
        icon: Icons.group_add_outlined,
        subtitle:
            'Ваша ссылка — 17,5% нетто с тех, кто по ней зарегистрировался',
        onTap: () => context.push(PartnerProgramRoute.path),
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
        title: 'Заказать рекламу',
        icon: Icons.campaign_outlined,
        subtitle: 'Заявка: объявление в ленте, рилсах или каналах',
        onTap: () => context.push(AdsHubRoute.path),
      ),
      _SettingsItem(
        title: 'Доп. реклама за долю',
        icon: Icons.percent_outlined,
        subtitle: 'Больше объявлений — 35% нетто с рекламы на вас',
        onTap: () => context.push(ExtraAdsRoute.path),
      ),
      _SettingsItem(
        title: 'Поддержка и безопасность',
        icon: Icons.verified_user_outlined,
        subtitle: 'Конфиденциальность, модерация, жалобы, правила сообщества',
        onTap: () => context.push(SupportSecurityRoute.path),
      ),
      _SettingsItem(
        title: 'Чёрный список',
        icon: Icons.block_outlined,
        subtitle: 'Заблокированные пользователи',
        onTap: () => context.push(BlockedUsersRoute.path),
      ),
      _SettingsItem(
        title: 'Резервная копия',
        icon: Icons.backup_outlined,
        subtitle: 'Экспорт и восстановление профиля (JSON)',
        onTap: () => context.push(BackupRoute.path),
      ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Возвраты подписок',
          icon: Icons.currency_exchange_outlined,
          subtitle: 'Очередь запросов на возврат',
          onTap: () => context.push(AdminRefundQueueRoute.path),
        ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Выплаты партнёрам',
          icon: Icons.payments_outlined,
          subtitle: 'Заявки на карту / СБП с партнёрского баланса',
          onTap: () => context.push(AdminPartnerPayoutsRoute.path),
        ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Выплаты авторам',
          icon: Icons.account_balance_wallet_outlined,
          subtitle: 'Заявки авторов на карту / СБП',
          onTap: () => context.push(AdminCreatorPayoutsRoute.path),
        ),
      if (_isAdmin)
        _SettingsItem(
          title: 'Обращения в поддержку',
          icon: Icons.support_agent_outlined,
          subtitle: 'Открытые тикеты и приоритетная очередь',
          onTap: () => context.push(AdminSupportTicketsRoute.path),
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
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(FeedRoute.path);
            }
          },
        ),
      ),
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
                    _ThemeChoiceGrid(
                      selected: ref.watch(themeModeProvider),
                      onSelected: (choice) {
                        ref.read(themeModeProvider.notifier).setChoice(choice);
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
                title: const Text('Вибро-отсчёт медленного режима'),
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
                  'Автоматически повторять отправку после медленного режима и антифлуда',
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
                    subtitle: Text(lastSeenPrivacyLabel(_lastSeenPrivacy)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _privacyBusy ? null : _pickLastSeenPrivacy,
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
                        'Кто может писать вам без оплаты звёздами',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.push(PaidMessageExceptionsRoute.path),
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

/// Four large theme tiles so light actually applies and midnight is reachable.
class _ThemeChoiceGrid extends StatelessWidget {
  const _ThemeChoiceGrid({
    required this.selected,
    required this.onSelected,
  });

  final AppThemeChoice selected;
  final ValueChanged<AppThemeChoice> onSelected;

  static const _options = [
    _ThemeChoice(
      AppThemeChoice.system,
      Icons.brightness_auto,
      'Системная',
      Color(0xFF8A94A6),
    ),
    _ThemeChoice(
      AppThemeChoice.light,
      Icons.light_mode,
      'Светлая',
      Color(0xFFF4F4F5),
    ),
    _ThemeChoice(
      AppThemeChoice.dark,
      Icons.dark_mode,
      'Тёмная',
      Color(0xFF0F1319),
    ),
    _ThemeChoice(
      AppThemeChoice.midnight,
      Icons.contrast,
      'Полночь',
      Color(0xFF000000),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        for (final option in _options)
          _ThemeChoiceTile(
            option: option,
            isSelected: selected == option.choice,
            onTap: () => onSelected(option.choice),
          ),
      ],
    );
  }
}

class _ThemeChoice {
  const _ThemeChoice(this.choice, this.icon, this.label, this.swatch);

  final AppThemeChoice choice;
  final IconData icon;
  final String label;
  final Color swatch;
}

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _ThemeChoice option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.7)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: option.swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.outline,
                    width: 1,
                  ),
                ),
                child: Icon(
                  option.icon,
                  size: 16,
                  color: option.choice == AppThemeChoice.light
                      ? const Color(0xFF111111)
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
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
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
