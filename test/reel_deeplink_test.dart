import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';

void main() {
  group('ReelByIdRoute.goPathFromBrowserPath', () {
    test('maps public and /app/ reel urls', () {
      expect(ReelByIdRoute.goPathFromBrowserPath('/reel/28'), '/reel/28');
      expect(ReelByIdRoute.goPathFromBrowserPath('/reel/28/'), '/reel/28');
      expect(ReelByIdRoute.goPathFromBrowserPath('/app/reel/28'), '/reel/28');
      expect(ReelByIdRoute.goPathFromBrowserPath('/app/reel/28?go=1'), '/reel/28');
    });

    test('ignores unrelated paths', () {
      expect(ReelByIdRoute.goPathFromBrowserPath('/reels'), isNull);
      expect(ReelByIdRoute.goPathFromBrowserPath('/post/28'), isNull);
      expect(ReelByIdRoute.goPathFromBrowserPath('/reel/abc'), isNull);
    });
  });

  group('parseDeepLinkToGoPath', () {
    test('https reel link opens /reel/:id', () {
      expect(
        parseDeepLinkToGoPath('https://haneat.app/reel/28'),
        '/reel/28',
      );
      expect(
        parseDeepLinkToGoPath('https://haneat.app/app/reel/28'),
        '/reel/28',
      );
    });

    test('haneat://reel/:id opens /reel/:id not /post/:id', () {
      expect(parseDeepLinkToGoPath('haneat://reel/28'), '/reel/28');
      expect(parseDeepLinkToGoPath('haneat://post/28'), '/post/28');
    });

    test('share text from a reel is an in-app path', () {
      const share = 'салют\n\nОткрыть в HanWe: https://haneat.app/reel/28';
      final match = RegExp(r'https?://[^\s]+').firstMatch(share);
      expect(match, isNotNull);
      expect(parseDeepLinkToGoPath(match!.group(0)!), '/reel/28');
    });
  });
}
