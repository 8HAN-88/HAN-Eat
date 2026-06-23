import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/api_error_parser.dart';

Future<bool> showChangeEmailDialog(
  BuildContext context, {
  required String currentEmail,
}) async {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый email'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'На новый адрес придёт письмо с подтверждением. '
                'До подтверждения вход остаётся по текущему email.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Новый email',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!email.contains('@') || !email.contains('.')) {
                    return 'Введите корректный email';
                  }
                  if (email.toLowerCase() == currentEmail.toLowerCase()) {
                    return 'Это уже ваш текущий email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Текущий пароль',
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) return 'Введите пароль';
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
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return false;

    final result = await AuthService.changeEmailRequest(
      newEmail: emailController.text.trim(),
      password: passwordController.text,
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
    emailController.dispose();
    passwordController.dispose();
  }
}

enum _EmailAction { change, resendVerification }

Future<void> showEmailManageSheet(
  BuildContext context, {
  required String email,
  required bool emailVerified,
  required VoidCallback onChanged,
}) async {
  final action = await showModalBottomSheet<_EmailAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              children: [
                Text(
                  email,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  emailVerified ? 'Email подтверждён' : 'Email не подтверждён',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: emailVerified
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.error,
                      ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Изменить email'),
            onTap: () => Navigator.pop(ctx, _EmailAction.change),
          ),
          if (!emailVerified)
            ListTile(
              leading: const Icon(Icons.mark_email_read_outlined),
              title: const Text('Отправить письмо повторно'),
              onTap: () => Navigator.pop(ctx, _EmailAction.resendVerification),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;

  if (action == _EmailAction.change) {
    await showChangeEmailDialog(context, currentEmail: email);
    return;
  }

  try {
    final result = await AuthService.resendVerification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    onChanged();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userVisibleError(e))),
    );
  }
}

/// Строка «Эл. почта» в профиле (как номер телефона).
class ProfileEmailTile extends StatelessWidget {
  const ProfileEmailTile({
    super.key,
    required this.email,
    required this.emailVerified,
    required this.onChanged,
  });

  final String email;
  final bool emailVerified;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = emailVerified
        ? email
        : '$email · не подтверждён';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.email_outlined),
        title: const Text('Эл. почта'),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showEmailManageSheet(
          context,
          email: email,
          emailVerified: emailVerified,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
