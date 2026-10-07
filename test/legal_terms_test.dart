import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/services/legal_service.dart';

void main() {
  test('user agreement shields the operator and matches the consent version', () {
    final html = File('static/legal/terms.html').readAsStringSync();
    expect(html, contains('2026-10-07'));
    expect(html, contains('публичной офертой'));
    expect(html, contains('информационный посредник'));
    expect(html, contains('1253.1'));
    expect(html, contains('149-ФЗ'));
    expect(html, contains('не является средством массовой информации'));
    expect(html, contains('не аффилирован'));
    expect(html, contains('как есть'));
    expect(html, contains('Запрещается'));
    expect(html, contains('несовершеннолетних'));
    expect(html, contains('support@haneat.app'));
    expect(html, contains('обязательные права потребителя'));
    expect(html, contains('виртуальные объекты'));
    expect(html, contains('Рекламодатель'));
    expect(html, contains('Претензионный порядок'));
    expect(html, contains('Российской Федерации'));
    expect(html, isNot(contains('тарифы AI, Creator, Pro')));
    expect(LegalService.fallbackStatus().version, '2026-10-07');
  });

  test('leftover agreement hashes open the legal screen', () {
    expect(shortcutPathAlias('/oferta'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/publichnaya-oferta'), SupportSecurityRoute.path);
    expect(shortcutPathAlias('/soglashenie'), SupportSecurityRoute.path);
    expect(
      shortcutPathAlias('/polzovatelskoe-soglashenie'),
      SupportSecurityRoute.path,
    );
    expect(shortcutPathAlias('/user-agreement'), SupportSecurityRoute.path);
    expect(leftoverPathAlias('/go/oferta'), SupportSecurityRoute.path);
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/soglashenie'),
      SupportSecurityRoute.path,
    );
    expect(shortcutPathAlias('/reels'), isNull);
    expect(shortcutPathAlias('/logout'), isNull);
  });
}
