import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _newEmailController = TextEditingController();
  final _emailPasswordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newEmailController.dispose();
    _emailPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароли не совпадают')),
      );
      return;
    }
    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новый пароль — минимум 8 символов')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await AuthService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeEmail() async {
    final email = _newEmailController.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректный email')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await AuthService.changeEmailRequest(
        newEmail: email,
        password: _emailPasswordController.text,
      );
      if (mounted) {
        _newEmailController.clear();
        _emailPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Безопасность аккаунта')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null)
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(user.email),
              subtitle: Text(
                user.emailVerified ? 'Email подтверждён' : 'Email не подтверждён',
              ),
            ),
          const SizedBox(height: 8),
          Text('Смена пароля', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _currentPasswordController,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Текущий пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newPasswordController,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Новый пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Повторите новый пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _changePassword,
            child: const Text('Сохранить пароль'),
          ),
          const Divider(height: 32),
          Text('Смена email', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'На новый адрес придёт письмо с подтверждением. До подтверждения вход остаётся по старому email.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Новый email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailPasswordController,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Пароль для подтверждения',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _loading ? null : _changeEmail,
            child: const Text('Запросить смену email'),
          ),
        ],
      ),
    );
  }
}
