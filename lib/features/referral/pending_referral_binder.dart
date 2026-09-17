import '../../services/auth_service.dart';
import '../../services/pending_referral_store.dart';
import '../../services/revenue_share_service.dart';
import '../../utils/api_error_parser.dart';

/// Привязывает аккаунт к ссылке приглашения и кэширует свою ссылку.
///
/// HTML кладёт `?ref=` в store до Flutter. Регистрация / Google шлют токен
/// сами. Этот хук закрывает вход, подтверждение почты и холодный старт.
class PendingReferralBinder {
  PendingReferralBinder._();

  static bool _inFlight = false;

  static Future<void> applyIfNeeded() async {
    if (_inFlight) return;
    if (AuthService.instance.currentUser == null) return;
    _inFlight = true;
    try {
      final pending = await PendingReferralStore.peek();
      if (pending != null) {
        try {
          await RevenueShareApi.applyCode(pending);
        } on ApiClientException {
          // Просроченный или чужой аккаунт не должен выкидывать ссылку:
          // следующий человек на этом телефоне ещё сможет привязаться.
        } catch (_) {
          // Сеть — оставим токен, попробуем позже.
        }
      }
      final official = await PendingReferralStore.officialCode();
      if (official == null) {
        try {
          await RevenueShareApi.me();
        } catch (_) {}
      }
    } finally {
      _inFlight = false;
    }
  }
}
