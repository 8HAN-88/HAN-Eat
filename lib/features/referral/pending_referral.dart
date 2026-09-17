/// Нормализация реферального кода из ссылки, поля или `?ref=`.
class PendingReferral {
  const PendingReferral._();

  static const prefsKey = 'pending_referral';
  static const officialCodeKey = 'referral_code';
  static const webInviteBase = 'https://haneat.app/invite';

  static final _zw = RegExp(r'[\u200b\u200c\u200d\ufeff\u00ad]');
  static final _trailPunct = RegExp(r'''[.,;:!?\)\]\}'"…/]+$''');

  static String _sanitize(String raw) {
    var value = raw.replaceAll(_zw, '');
    value = value.replaceAll('\u00a0', ' ');
    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('&AMP;', '&')
        .replaceAll('&#38;', '&');
    return value.trim();
  }

  static String? normalize(String? raw) {
    var value = _sanitize(raw ?? '');
    if (value.isEmpty || value.length > 100) return null;
    if (value.startsWith('@')) {
      value = value.substring(1).trim();
    }
    value = value.replaceAll(_trailPunct, '');
    if (value.isEmpty || value.length > 100) return null;
    return value;
  }

  static String? _queryValue(Uri uri, List<String> names) {
    final wanted = {for (final name in names) name.toLowerCase()};
    for (final entry in uri.queryParameters.entries) {
      var key = entry.key.toLowerCase();
      if (key.startsWith('amp;')) key = key.substring(4);
      if (!wanted.contains(key)) continue;
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Код из `?ref=` / `?REF=` / `?referral=` у уже разобранного URI.
  static String? queryRef(Uri? uri) {
    if (uri == null) return null;
    return extract(uri.toString());
  }

  /// Достаёт код из сырого ввода: `ABC12XYZ`, `@alice`, `u12`,
  /// `https://haneat.app/invite?ref=ABC12XYZ`, обёрток `?u=` / `?url=`.
  static String? extract(String? raw, {int depth = 0}) {
    final value = _sanitize(raw ?? '');
    if (value.isEmpty || depth > 3) return null;
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final ref = _queryValue(uri, const ['ref', 'referral']);
      if (ref != null && ref.isNotEmpty) {
        if (ref.contains('://') || ref.toLowerCase().contains('ref=')) {
          final inner = extract(ref, depth: depth + 1);
          if (inner != null) return inner;
        }
        return normalize(ref);
      }
      final frag = uri.fragment;
      if (frag.toLowerCase().contains('ref=')) {
        final fragUri = Uri.tryParse(
          frag.startsWith('/')
              ? 'https://haneat.app$frag'
              : 'https://haneat.app/$frag',
        );
        final href = fragUri == null
            ? null
            : _queryValue(fragUri, const ['ref', 'referral']);
        if (href != null && href.isNotEmpty) {
          return extract(href, depth: depth + 1) ?? normalize(href);
        }
      }
      for (final key in const ['u', 'url', 'q', 'to', 'link', 'text']) {
        final nested = uri.queryParameters[key]?.trim();
        if (nested == null || nested.isEmpty) continue;
        if (nested.toLowerCase().contains('haneat.app') ||
            nested.toLowerCase().contains('ref=')) {
          final inner = extract(nested, depth: depth + 1);
          if (inner != null) return inner;
        }
      }
    }
    final embedded = RegExp(
      r'https?://(?:www\.)?haneat\.app[^\s<>]+',
      caseSensitive: false,
    ).firstMatch(value);
    if (embedded != null && embedded.group(0) != value) {
      final inner = extract(embedded.group(0), depth: depth + 1);
      if (inner != null) return inner;
    }
    // Ссылка без ?ref= — это не код. Иначе /app/ становится «инвайтом».
    if (value.contains('://') || value.toLowerCase().contains('haneat.app')) {
      return null;
    }
    return normalize(value);
  }

  /// Этот аккаунт уже привязан именно к этой ссылке — токен можно стереть.
  /// Чужой/просроченный apply не должен выкидывать приглашение с устройства.
  static bool boundTo(
    String? pending, {
    String? referredByCode,
    String? referredByUsername,
    int? referredById,
  }) {
    final token = extract(pending);
    if (token == null) return false;
    final lower = token.toLowerCase();
    final code = extract(referredByCode);
    if (code != null && code.toLowerCase() == lower) return true;
    final username = normalize(referredByUsername);
    if (username != null && username.toLowerCase() == lower) return true;
    if (referredById != null && lower == 'u$referredById') return true;
    return false;
  }

  static String shareUrl(String code) {
    final ref = extract(code) ?? code.trim();
    if (ref.isEmpty) return webInviteBase;
    return '$webInviteBase?ref=${Uri.encodeComponent(ref)}';
  }
}
