/// Нормализация реферального кода из ссылки, поля или `?ref=`.
class PendingReferral {
  const PendingReferral._();

  static const prefsKey = 'pending_referral';
  static const officialCodeKey = 'referral_code';
  static const webInviteBase = 'https://haneat.app/invite';

  static String? normalize(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty || value.length > 100) return null;
    if (value.startsWith('@')) {
      value = value.substring(1).trim();
    }
    if (value.isEmpty || value.length > 100) return null;
    return value;
  }

  /// Достаёт код из сырого ввода: `ABC12XYZ`, `@alice`, `u12`,
  /// `https://haneat.app/invite?ref=ABC12XYZ`.
  static String? extract(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final ref = uri.queryParameters['ref']?.trim();
      if (ref != null && ref.isNotEmpty) {
        return normalize(ref);
      }
      final frag = uri.fragment;
      if (frag.contains('ref=')) {
        final fragUri = Uri.tryParse(
          frag.startsWith('/')
              ? 'https://haneat.app$frag'
              : 'https://haneat.app/$frag',
        );
        final href = fragUri?.queryParameters['ref']?.trim();
        if (href != null && href.isNotEmpty) {
          return normalize(href);
        }
      }
    }
    return normalize(value);
  }

  static String shareUrl(String code) {
    final ref = extract(code) ?? code.trim();
    if (ref.isEmpty) return webInviteBase;
    return '$webInviteBase?ref=${Uri.encodeComponent(ref)}';
  }
}
