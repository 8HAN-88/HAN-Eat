import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../app/router_keys.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/api_error_parser.dart';

/// Подтверждённый выход из аккаунта (единый UX).
Future<void> confirmAndSignOut(BuildContext context) async {
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => const _SignOutDialog(),
  );
}

class _SignOutDialog extends StatefulWidget {
  const _SignOutDialog();

  @override
  State<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<_SignOutDialog> {
  bool _working = false;

  GoRouter _router() {
    final root = hanEatRootNavigatorKey.currentContext;
    if (root != null) return GoRouter.of(root);
    return GoRouter.of(context);
  }

  Future<void> _signOut() async {
    if (_working) return;
    if (!AuthService.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сервис авторизации не инициализирован'),
        ),
      );
      return;
    }

    setState(() => _working = true);
    try {
      await AuthService.instance.signOut(notifySession: false);
      if (UserService.isInitialized) {
        UserService.instance.profile.value = null;
      }
      if (!mounted) return;

      final router = _router();
      final loc = GoRouterState.of(context).matchedLocation.split('?').first;
      if (loc != LoginRoute.path) {
        router.go(LoginRoute.path);
      }

      AuthService.instance.notifySessionCleared();

      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e, fallback: 'Не удалось выйти')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_working,
      child: AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: _working
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Выход из аккаунта...'),
                ],
              )
            : const Text('Вы уверены, что хотите выйти?'),
        actions: _working
            ? null
            : [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: _signOut,
                  child: const Text('Выйти'),
                ),
              ],
      ),
    );
  }
}
