/// Нормализация и проверка http(s) URL для постов-ссылок.
String? normalizeHttpUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final schemeMatch = RegExp(r'^([a-z][a-z0-9+.-]*):', caseSensitive: false)
      .firstMatch(trimmed);
  if (schemeMatch != null) {
    final scheme = schemeMatch.group(1)!.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
  }

  final candidate =
      trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri.toString();
}

/// Сообщение об ошибке или `null`, если URL корректен.
String? validateHttpUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Введите ссылку';
  }
  if (normalizeHttpUrl(raw) == null) {
    return 'Некорректный адрес (нужен http:// или https://)';
  }
  return null;
}
