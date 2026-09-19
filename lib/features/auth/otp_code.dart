/// Короткий код подтверждения — как у Apple / Google / банков.
const kOtpCodeLength = 6;
const kOtpResendCooldown = Duration(seconds: 60);

String normalizeOtpInput(String raw) {
  return raw.replaceAll(RegExp(r'[\s-]'), '');
}

bool isOtpCode(String raw) {
  return RegExp(r'^\d{6}$').hasMatch(normalizeOtpInput(raw));
}

/// Старые письма со ссылкой всё ещё несут длинный токен.
bool isLegacyAuthToken(String raw) {
  return normalizeOtpInput(raw).length >= 16;
}

bool isAcceptableAuthCode(String raw) {
  return isOtpCode(raw) || isLegacyAuthToken(raw);
}
