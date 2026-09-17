import '../../services/auth_service.dart';
import '../../services/pending_referral_store.dart';
import '../../services/revenue_share_service.dart';
import '../../utils/api_error_parser.dart';

/// Привязывает аккаунт к ссылке приглашения, если человек уже вошёл.
///
/// HTML кладёт `?ref=` в store до Flutter. Регистрация отправляет токен сама.
/// Этот хук закрывает вход по той же ссылке и холодный старт с сессией.
class PendingReferralBinder {
  PendingReferralBinder._();

  static bool _inFlight = false;

  static Future<void> applyIfNeeded() async {
    if (_inFlight) return;
    if (AuthService.instance.currentUser == null) return;
    final pending = await PendingReferralStore.peek();
    if (pending == null) return;
    _inFlight = true;
    try {
      await RevenueShareApi.applyCode(pending);
    } on ApiClientException catch (e) {
      final status = e.statusCode ?? 0;
      if (status >= 400 && status < 500) {
        await PendingReferralStore.clear();
      }
    } catch (_) {
      // Сеть — оставим токен, попробуем позже.
    } finally {
      _inFlight = false;
    }
  }
}
