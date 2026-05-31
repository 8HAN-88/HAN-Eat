import 'package:flutter/foundation.dart';

/// URL возврата после оплаты ЮKassa (web vs deep link в приложении).
abstract final class SubscriptionCheckoutUrls {
  static const successPath = '/subscription/success';
  static const cancelPath = '/subscription/cancel';

  static String successUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}$successPath?session_id={CHECKOUT_SESSION_ID}';
    }
    return 'haneat://subscription/success';
  }

  static String cancelUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}$cancelPath';
    }
    return 'haneat://subscription/cancel';
  }
}
