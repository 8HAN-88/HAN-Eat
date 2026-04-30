import 'package:flutter/material.dart';

class SupportSecurityScreen extends StatelessWidget {
  const SupportSecurityScreen({super.key});

  Future<void> _launchEmail() async {
    // Простая реализация без url_launcher
    // В реальном приложении можно использовать url_launcher
    // final uri = Uri.parse('mailto:support@haneat.app');
    // if (await canLaunchUrl(uri)) {
    //   await launchUrl(uri);
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка и безопасность')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // GDPR и конфиденциальность
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Конфиденциальность и GDPR'),
                  subtitle: const Text('Политика конфиденциальности и обработка данных'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Конфиденциальность и GDPR'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'HAN Eat соблюдает все требования GDPR и защищает ваши персональные данные.\n\n'
                            'Мы собираем только необходимую информацию для работы приложения:\n'
                            '• Данные профиля (имя, аватар)\n'
                            '• История поиска (локально)\n'
                            '• Настройки приложения\n\n'
                            'Ваши данные не передаются третьим лицам без вашего согласия.\n\n'
                            'Вы можете запросить удаление всех ваших данных в любое время.',
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
                  leading: const Icon(Icons.security),
                  title: const Text('Безопасность данных'),
                  subtitle: const Text('Как мы защищаем вашу информацию'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Безопасность данных'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Мы используем современные методы защиты:\n\n'
                            '• Шифрование данных при передаче (HTTPS)\n'
                            '• Безопасное хранение в Firebase\n'
                            '• Регулярные обновления безопасности\n'
                            '• Аутентификация через Firebase Auth\n\n'
                            'Ваши пароли никогда не хранятся в открытом виде.',
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
          // Модерация
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Модерация контента'),
                  subtitle: const Text('Правила сообщества и модерация'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Модерация контента'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Правила сообщества:\n\n'
                            '• Запрещено публиковать оскорбительный контент\n'
                            '• Запрещено спамить или рекламировать\n'
                            '• Уважайте других пользователей\n'
                            '• Контент должен быть связан с кулинарией\n\n'
                            'Нарушение правил может привести к блокировке аккаунта.',
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
                  subtitle: const Text('Сообщить о нарушении правил'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Пожаловаться'),
                        content: const Text(
                          'Если вы обнаружили контент, нарушающий правила сообщества, '
                          'пожалуйста, сообщите нам об этом.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Жалоба отправлена. Спасибо!'),
                                ),
                              );
                            },
                            child: const Text('Отправить жалобу'),
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
          // Поддержка
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Помощь и поддержка'),
                  subtitle: const Text('Часто задаваемые вопросы'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('FAQ будет доступен в ближайшее время'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Связаться с нами'),
                  subtitle: const Text('support@haneat.app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Email: support@haneat.app'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Сообщить об ошибке'),
                  subtitle: const Text('Помогите улучшить приложение'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Форма отправки ошибок будет доступна в ближайшее время'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // О приложении
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('О приложении'),
              subtitle: const Text('Версия 1.0.0'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'HAN Eat',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.restaurant_menu, size: 48),
                  children: [
                    const Text('Приложение для поиска рецептов и планирования питания.'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

