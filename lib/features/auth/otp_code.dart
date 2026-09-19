/// Короткий код подтверждения — как у Apple / Google / банков.
const kOtpCodeLength = 6;
const kOtpResendCooldown = Duration(seconds: 60);

String normalizeOtpInput(String raw) {
  final trimmed = raw.trim();
  final compact = trimmed.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\d{6}$').hasMatch(compact)) {
    return compact;
  }
  return trimmed;
}

bool isOtpCode(String raw) {
  return RegExp(r'^\d{6}$').hasMatch(normalizeOtpInput(raw));
}

/// Старые письма со ссылкой всё ещё несут длинный токен.
bool isLegacyAuthToken(String raw) {
  return raw.trim().length >= 16 && !isOtpCode(raw);
}

bool isAcceptableAuthCode(String raw) {
  return isOtpCode(raw) || isLegacyAuthToken(raw);
}

/// 6 цифр из клеток или длинный токен из письма — без вырезания `-`.
String resolveAuthCode({required String typed, String? linkToken}) {
  final otp = normalizeOtpInput(typed);
  if (isOtpCode(otp)) return otp;
  final link = (linkToken ?? '').trim();
  if (isLegacyAuthToken(link)) return link;
  return otp;
}
