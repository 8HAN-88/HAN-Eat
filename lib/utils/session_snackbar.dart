import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../core/network/feed_load_helper.dart';

/// SnackBar с кнопкой «Войти» при истёкшей сессии.
void showSessionExpiredSnackBar(BuildContext context, {String? message}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message ?? 'Сессия истекла. Войдите снова.'),
      action: SnackBarAction(
        label: 'Войти',
        onPressed: () => context.go(LoginRoute.path),
      ),
      duration: const Duration(seconds: 5),
    ),
  );
}

void showErrorSnackBar(
  BuildContext context,
  Object error, {
  String? fallback,
  String? authFallback,
}) {
  if (FeedLoadHelper.isSessionError(error)) {
    showSessionExpiredSnackBar(context);
    return;
  }
  final text = error.toString().replaceAll('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text.isNotEmpty ? text : (fallback ?? 'Ошибка'))),
  );
}
