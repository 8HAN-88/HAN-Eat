import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Должен совпадать с PHONE_HASH_PEPPER на backend (по умолчанию haneat-phone-v1).
const kPhoneHashPepper = 'haneat-phone-v1';

/// Нормализация номера в E.164 (упор на RU, как у большинства пользователей).
String? normalizePhoneE164(String raw, {String defaultRegion = 'RU'}) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  var d = digits;
  if (d.startsWith('00')) d = d.substring(2);
  final region = defaultRegion.toUpperCase();
  if (region == 'RU') {
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    if (d.length == 11 && d.startsWith('7')) return '+$d';
    if (d.length == 10) return '+7$d';
  }
  if (d.length >= 10 && d.length <= 15) return '+$d';
  return null;
}

String hashPhoneE164(String e164) {
  final payload = utf8.encode('$kPhoneHashPepper:$e164');
  return sha256.convert(payload).toString();
}

String? hashPhoneRaw(String raw, {String defaultRegion = 'RU'}) {
  final e164 = normalizePhoneE164(raw, defaultRegion: defaultRegion);
  if (e164 == null) return null;
  return hashPhoneE164(e164);
}
