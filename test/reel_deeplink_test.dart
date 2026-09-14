import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/services/share_link_service.dart';

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

  group('ReelByIdRoute.postIdFromUrl', () {
    test('reads public, /app and native reel links', () {
      expect(ReelByIdRoute.postIdFromUrl('https://haneat.app/reel/28'), 28);
      expect(ReelByIdRoute.postIdFromUrl('https://haneat.app/app/reel/28'), 28);
      expect(ReelByIdRoute.postIdFromUrl('haneat://reel/28'), 28);
    });

    test('ignores other links', () {
      expect(ReelByIdRoute.postIdFromUrl('https://haneat.app/post/28'), isNull);
      expect(ReelByIdRoute.postIdFromUrl('https://yandex.ru/pogoda'), isNull);
    });
  });

  group('ShareLinkService.visibleCaptionForReelShare', () {
    test('keeps user text and drops the HanWe reel url', () {
      expect(
        ShareLinkService.visibleCaptionForReelShare(
          'салют\n\nОткрыть в HanWe: https://haneat.app/reel/28',
        ),
        'салют',
      );
      expect(
        ShareLinkService.visibleCaptionForReelShare(
          'Открыть в HanWe: https://haneat.app/reel/28',
        ),
        isEmpty,
      );
    });
  });

  group('PostFeedRoute.postIdFromUrl', () {
    test('reads public, channel and native post links', () {
      expect(PostFeedRoute.postIdFromUrl('https://haneat.app/post/28'), 28);
      expect(PostFeedRoute.postIdFromUrl('https://haneat.app/app/post/28'), 28);
      expect(
        PostFeedRoute.postIdFromUrl('https://haneat.app/channel/5/post/99'),
        99,
      );
      expect(PostFeedRoute.postIdFromUrl('haneat://post/28'), 28);
    });

    test('ignores reel and foreign links', () {
      expect(PostFeedRoute.postIdFromUrl('https://haneat.app/reel/28'), isNull);
      expect(PostFeedRoute.postIdFromUrl('https://yandex.ru/pogoda'), isNull);
    });
  });

  group('ShareLinkService.sharedPostIdFromUrl', () {
    test('accepts reel, post and channel post links', () {
      expect(ShareLinkService.sharedPostIdFromUrl('https://haneat.app/reel/7'), 7);
      expect(ShareLinkService.sharedPostIdFromUrl('https://haneat.app/post/8'), 8);
      expect(
        ShareLinkService.sharedPostIdFromUrl(
          'https://haneat.app/channel/2/post/11',
        ),
        11,
      );
    });
  });

  group('ShareLinkService.visibleCaptionForSharedPost', () {
    test('drops post and channel share urls', () {
      expect(
        ShareLinkService.visibleCaptionForSharedPost(
          'смотри\n\nОткрыть в HanWe: https://haneat.app/post/28',
        ),
        'смотри',
      );
      expect(
        ShareLinkService.visibleCaptionForSharedPost(
          'Открыть в HanWe: https://haneat.app/channel/4/post/9',
        ),
        isEmpty,
      );
    });
  });
}
