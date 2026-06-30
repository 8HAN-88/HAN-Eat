import 'package:shared_preferences/shared_preferences.dart';

/// Локальное хранилище токенов ботов.
/// Позволяет пользователю повторно копировать токен позже.
class BotTokenStorage {
  static const _prefix = 'bot_token_';

  static Future<void> saveToken(int botId, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$botId', token);
  }

  static Future<String?> getToken(int botId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$botId');
  }

  static Future<void> removeToken(int botId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$botId');
  }
}
