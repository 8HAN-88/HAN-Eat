import 'dart:async';

import '../../services/auth_service.dart';

/// Сообщения при показе [FeedApiCache] после ошибки загрузки.
class FeedLoadHelper {
  static bool isSessionError(Object e) {
    if (e is AuthException) {
      final m = e.message;
      return m.contains('Сессия истекла') ||
          m.contains('Token refresh failed') ||
          m.contains('No refresh token');
    }
    final s = e.toString();
    if (s.contains('Сервер недоступен') ||
        s.contains('Превышено время ожидания')) {
      return false;
    }
    return s.contains('Сессия истекла') ||
        s.contains('Token refresh failed') ||
        s.contains('No refresh token') ||
        s.contains('Invalid refresh token');
  }

  static bool isNetworkError(Object e) {
    final s = e.toString();
    return e is TimeoutException ||
        s.contains('Connection refused') ||
        s.contains('Failed host lookup') ||
        s.contains('Failed to fetch') ||
        s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Сервер недоступен') ||
        s.contains('Превышено время ожидания');
  }

  static String cacheSnackMessage(Object e) {
    if (isSessionError(e)) {
      return 'Сессия истекла. Войдите снова. Показаны сохранённые посты.';
    }
    if (isNetworkError(e)) {
      return 'Нет сети или сервер недоступен. Показан сохранённый кеш.';
    }
    return 'Не удалось обновить ленту. Показан сохранённый кеш.';
  }

  /// Короткое сообщение для пустого состояния ленты (без кеша).
  static String feedLoadErrorMessage(Object e) {
    if (isSessionError(e)) {
      return 'Сессия истекла. Войдите снова.';
    }
    if (e is TimeoutException || isNetworkError(e)) {
      return 'Сервер недоступен. Проверьте сеть и обновите ленту.';
    }
    final raw = e.toString().replaceAll('Exception: ', '');
    if (raw.length > 120) {
      return 'Не удалось загрузить ленту. Потяните вниз, чтобы обновить.';
    }
    return 'Не удалось загрузить ленту: $raw';
  }

  static String cacheBannerMessage(Object e) {
    if (e == 'offline') {
      return 'Нет сети. Показано из сохранённого кеша';
    }
    if (isSessionError(e)) {
      return 'Сессия истекла — войдите снова. Показано из кеша';
    }
    return 'Показано из сохранённого кеша';
  }

  /// Сбрасывает просроченную сессию, чтобы роутер отправил на экран входа.
  static Future<void> clearSessionIfExpired(Object e) async {
    if (!isSessionError(e)) return;
    await AuthService.logout();
  }
}
