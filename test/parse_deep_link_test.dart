import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';

void main() {
  test('PWA /app/ is not a GoRouter location', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/app/?go=1'), isNull);
    expect(parseDeepLinkToGoPath('https://www.haneat.app/app/index.html'), isNull);
  });

  test('strips /app prefix from deep links', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/feed'), '/feed');
    expect(parseDeepLinkToGoPath('https://haneat.app/feed'), '/feed');
  });

  test('username links still resolve', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/@alice'),
      UsernameDeepLinkRoute.pathFor('alice'),
    );
  });
}
