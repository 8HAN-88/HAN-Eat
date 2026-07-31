import 'package:flutter/foundation.dart';

/// URL возврата после покупки Stars (web vs deep link в приложении).
abstract final class StarsCheckoutUrls {
  static const successPath = '/paid/success';
  static const cancelPath = '/paid/cancel';

  static String successUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}$successPath';
    }
    return 'haneat://paid/success';
  }

  static String cancelUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}$cancelPath';
    }
    return 'haneat://paid/cancel';
  }
}
