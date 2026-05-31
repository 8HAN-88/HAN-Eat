import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Читает ключ из `.env` только если [dotenv] уже загружен (иначе null).
String? dotenvString(String key) {
  try {
    if (!dotenv.isInitialized) return null;
    final v = dotenv.env[key]?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  } catch (_) {
    return null;
  }
}
