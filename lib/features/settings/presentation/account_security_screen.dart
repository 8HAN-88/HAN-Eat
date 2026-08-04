import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';

/// Центр безопасности аккаунта: активная сессия и быстрые действия.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт и безопасность')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Текущая сессия'),
              subtitle: Text(
                user == null
                    ? 'Неизвестный пользователь'
                    : '${user.email}\nВход выполнен',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Пароль и вход'),
                  subtitle: const Text('Смена пароля, email и вход через провайдеры'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(ProfileAuthRoute.path),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Двухфакторная защита'),
                  subtitle: Text('Скоро: TOTP / SMS. Пока недоступно.'),
                  enabled: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _logoutEverywhere,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: const Text('Завершить все сеансы'),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutEverywhere() async {
    setState(() => _busy = true);
    try {
      await AuthService.logout();
      if (!mounted) return;
      context.go(LoginRoute.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
