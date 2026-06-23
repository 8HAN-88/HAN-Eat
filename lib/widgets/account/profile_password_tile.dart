import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/api_error_parser.dart';

Future<bool> showChangePasswordDialog(BuildContext context) async {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый пароль'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: currentController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Текущий пароль',
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) return 'Введите текущий пароль';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль',
                ),
                validator: (value) {
                  final pwd = value ?? '';
                  if (pwd.length < 8) return 'Минимум 8 символов';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                ),
                validator: (value) {
                  if (value != newController.text) {
                    return 'Пароли не совпадают';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return false;

    final result = await AuthService.changePassword(
      currentPassword: currentController.text,
      newPassword: newController.text,
    );
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    return true;
  } on AuthException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
    return false;
  } finally {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }
}

Future<void> showPasswordManageSheet(BuildContext context) async {
  final change = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Пароль',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Изменить пароль'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
  if (change == true && context.mounted) {
    await showChangePasswordDialog(context);
  }
}

/// Строка «Пароль» в профиле (как номер телефона).
class ProfilePasswordTile extends StatelessWidget {
  const ProfilePasswordTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Пароль'),
        subtitle: const Text('Изменить пароль'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showPasswordManageSheet(context),
      ),
    );
  }
}
