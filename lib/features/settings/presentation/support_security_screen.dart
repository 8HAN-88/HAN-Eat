import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_router.dart';
import '../../../core/config/legal_urls.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/web_app_update_service.dart';
import 'blocked_users_screen.dart';

class SupportSecurityScreen extends StatelessWidget {
  const SupportSecurityScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть: $url')),
        );
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    await _openUrl(context, LegalUrls.supportEmail);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка и безопасность')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + floatingBottomPadding(context),
        ),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_person_outlined),
              title: const Text('Аккаунт и безопасность'),
              subtitle: const Text('Сессия, пароль, выход со всех устройств'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AccountSecurityRoute.path),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Политика конфиденциальности'),
                  subtitle: const Text('Открыть в браузере'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openUrl(context, LegalUrls.privacyPolicy),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Пользовательское соглашение'),
                  subtitle: const Text('Условия использования сервиса'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openUrl(context, LegalUrls.termsOfService),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Безопасность данных'),
                  subtitle: const Text('Как мы защищаем информацию'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Безопасность данных'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'HAN Eat использует:\n\n'
                            '• HTTPS при передаче данных\n'
                            '• JWT-авторизацию на наших серверах\n'
                            '• Хранение данных в защищённой базе (PostgreSQL)\n'
                            '• Хэширование паролей (не храним пароль в открытом виде)\n\n'
                            'Push-уведомления могут обрабатываться через Firebase Cloud Messaging.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Понятно'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Модерация контента'),
                  subtitle: const Text('Правила сообщества'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Модерация контента'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Правила сообщества:\n\n'
                            '• Запрещён оскорбительный контент и спам\n'
                            '• Уважайте других пользователей\n'
                            '• Контент должен быть связан с кулинарией\n\n'
                            'Нарушение правил может привести к ограничению аккаунта.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Понятно'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Пожаловаться на контент'),
                  subtitle: const Text('Сообщить о нарушении'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push(
                      SupportContactRoute.withSubjectMessage(
                        'Жалоба на контент',
                        'Опишите ссылку на пост/канал и суть нарушения.',
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Чёрный список'),
                  subtitle: const Text('Заблокированные пользователи'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Связаться с нами'),
                  subtitle: const Text('support@haneat.app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchEmail(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Сообщить об ошибке'),
                  subtitle: const Text('Помогите улучшить приложение'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(SupportContactRoute.bugReport()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('О приложении'),
              subtitle: const Text('Версия, условия и правовая информация'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'H.A.N. Eat',
                  applicationVersion:
                      kIsWeb && WebAppUpdateService.embeddedBuild.isNotEmpty
                          ? '1.0.0 (${WebAppUpdateService.embeddedBuild})'
                          : '1.0.0',
                  applicationLegalese:
                      '© H.A.N. Eat. Рецепты, план питания и сообщество.',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
