import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/api_error_parser.dart';

/// Подтверждённый выход из аккаунта (единый UX).
///
/// [navigateToLogin] — false, если экран сам показывает форму входа после выхода.
Future<void> confirmAndSignOut(
  BuildContext context, {
  bool navigateToLogin = true,
  VoidCallback? onSignedOut,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Выйти из аккаунта?'),
      content: const Text('Вы уверены, что хотите выйти?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Выйти'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  if (!AuthService.isInitialized) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сервис авторизации не инициализирован'),
      ),
    );
    return;
  }

  try {
    await AuthService.instance.signOut();
    if (UserService.isInitialized) {
      UserService.instance.profile.value = null;
    }
    if (!context.mounted) return;
    if (navigateToLogin) {
      context.go(LoginRoute.path);
    } else {
      onSignedOut?.call();
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось выйти'))),
    );
  }
}
