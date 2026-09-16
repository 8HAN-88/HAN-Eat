import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String html;

  setUpAll(() {
    html = File('web/index.html').readAsStringSync();
  });

  test('HTML register has no typed referral-code field', () {
    expect(html.contains('id="ref-wrap"'), isFalse);
    expect(html.contains('id="referral"'), isFalse);
    expect(html.contains('Код приглашения'), isFalse);
  });

  test('HTML register binds the invite link silently', () {
    expect(html.contains('body.referral_code = referral'), isTrue);
    expect(html.contains("prefSet('pending_referral', code)"), isTrue);
    expect(html.contains('function capturePendingReferral'), isTrue);
    expect(html.contains('extractReferral(prefGet(\'pending_referral\'))'), isTrue);
  });

  test('invite links open HTML signup from the unique URL', () {
    expect(html.contains("pendingRef && !hasSession()"), isTrue);
    expect(html.contains("setMode('register')"), isTrue);
    expect(html.contains('аккаунт привяжется к ссылке друга'), isTrue);
  });
}
