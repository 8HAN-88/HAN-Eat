import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/feed_load_helper.dart';
import 'api_error_parser.dart';

/// Ошибка в SnackBar. При истёкшей сессии — logout и редирект роутера (без «Войти»).
void showErrorSnackBar(
  BuildContext context,
  Object error, {
  String? fallback,
  VoidCallback? onRetry,
}) {
  if (FeedLoadHelper.isSessionError(error)) {
    unawaited(FeedLoadHelper.clearSessionIfExpired(error));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(userVisibleError(error, fallback: fallback ?? 'Ошибка')),
      action: onRetry == null
          ? null
          : SnackBarAction(label: 'Повторить', onPressed: onRetry),
    ),
  );
}
