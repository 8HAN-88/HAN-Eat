import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/flex_subscription_service.dart';

void main() {
  test('FlexMe disables checkout when payments are off', () {
    final me = FlexMe.fromJson({
      'current_level': 1,
      'price_rub': 39,
      'max_level': 79,
      'active': false,
      'levels': const [],
      'blocks': const [],
      'checkout_available': false,
      'legal_consent_required': false,
      'checkout_message': 'Оплата подписок временно недоступна',
    });
    expect(me.canCheckout, isFalse);
    expect(me.checkoutMessage, contains('недоступна'));
  });

  test('FlexMe requires legal consent before pay', () {
    final me = FlexMe.fromJson({
      'current_level': 1,
      'price_rub': 39,
      'max_level': 79,
      'active': false,
      'levels': const [],
      'blocks': const [],
      'checkout_available': true,
      'legal_consent_required': true,
      'checkout_message': 'Примите документы перед оплатой',
    });
    expect(me.canCheckout, isFalse);
    expect(me.legalConsentRequired, isTrue);
  });
}
