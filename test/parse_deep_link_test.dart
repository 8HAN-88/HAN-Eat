import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';

void main() {
  test('PWA /app/ is not a GoRouter location', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/app/?go=1'), isNull);
    expect(parseDeepLinkToGoPath('https://www.haneat.app/app/index.html'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/'), isNull);
    expect(parseDeepLinkToGoPath('https://haneat.app/?go=1'), isNull);
  });

  test('strips /app prefix from deep links', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/app/feed'), '/feed');
    expect(parseDeepLinkToGoPath('https://haneat.app/feed'), '/feed');
    expect(parseDeepLinkToGoPath('https://haneat.app/app/feed?go=1'), '/feed');
  });

  test('reads hash routes on the PWA shell', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/app/#/stories'),
      '/stories',
    );
    expect(parseDeepLinkToGoPath('https://haneat.app/app/#/'), isNull);
  });

  test('username links still resolve', () {
    expect(
      parseDeepLinkToGoPath('https://haneat.app/@alice'),
      UsernameDeepLinkRoute.pathFor('alice'),
    );
  });

  test('reel share links open /reel/:id', () {
    expect(parseDeepLinkToGoPath('https://haneat.app/reel/28'), '/reel/28');
    expect(parseDeepLinkToGoPath('https://haneat.app/app/reel/28'), '/reel/28');
    expect(parseDeepLinkToGoPath('haneat://reel/28'), '/reel/28');
  });
}
