import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String html;

  setUpAll(() {
    html = File('web/index.html').readAsStringSync();
  });

  test('HTML register has a visible referral field', () {
    expect(html.contains('id="ref-wrap"'), isTrue);
    expect(html.contains('id="referral"'), isTrue);
    expect(html.contains('Код приглашения'), isTrue);
  });

  test('HTML register sends referral_code and remembers ?ref=', () {
    expect(html.contains('body.referral_code = referral'), isTrue);
    expect(html.contains("prefSet('pending_referral', code)"), isTrue);
    expect(html.contains('function capturePendingReferral'), isTrue);
    expect(html.contains('function extractReferral'), isTrue);
    expect(html.contains("getElementById('ref-wrap').hidden = !isReg"), isTrue);
  });

  test('invite links open HTML signup, not only Flutter', () {
    expect(html.contains("pendingRef && !hasSession()"), isTrue);
    expect(html.contains("setMode('register')"), isTrue);
    expect(html.contains('Вас пригласили в HanWe'), isTrue);
  });
}
