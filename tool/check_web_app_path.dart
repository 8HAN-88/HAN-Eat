// Standalone check — без Flutter. Запуск: dart run tool/check_web_app_path.dart
import '../lib/app/web_app_path.dart';

int _failed = 0;

void check(String name, bool ok) {
  if (ok) {
    // ignore: avoid_print
    print('  OK  $name');
    return;
  }
  _failed++;
  // ignore: avoid_print
  print('  FAIL $name');
}

void eq(String name, Object? actual, Object? expected) {
  check('$name (${actual ?? 'null'} == ${expected ?? 'null'})', actual == expected);
}

void main() {
  check('shell /app', isWebAppShellPath('/app'));
  check('shell /app/', isWebAppShellPath('/app/'));
  check('shell /app/index.html', isWebAppShellPath('/app/index.html'));
  check('shell /index.html', isWebAppShellPath('/index.html'));
  check('not shell /feed', !isWebAppShellPath('/feed'));
  check('not shell /app/feed', !isWebAppShellPath('/app/feed'));

  check('go /', isGoRouterShellLocation('/'));
  check('go empty', isGoRouterShellLocation(''));
  check('go /?go=1', isGoRouterShellLocation('/?go=1'));
  check('go /app/?go=1', isGoRouterShellLocation('/app/?go=1'));
  check('go /index.html', isGoRouterShellLocation('/index.html'));
  check('not go /feed', !isGoRouterShellLocation('/feed'));
  check('not go /app/feed', !isGoRouterShellLocation('/app/feed'));

  eq('browser /app', browserPathToGoPath('/app'), null);
  eq('browser /app/', browserPathToGoPath('/app/'), null);
  eq('browser /', browserPathToGoPath('/'), null);
  eq('browser /app/feed', browserPathToGoPath('/app/feed'), '/feed');
  eq('browser /app/feed/', browserPathToGoPath('/app/feed/'), '/feed');
  eq('browser /app/@alice', browserPathToGoPath('/app/@alice'), '/@alice');
  eq('browser /feed', browserPathToGoPath('/feed'), '/feed');
  eq('browser /post/12', browserPathToGoPath('/post/12'), '/post/12');

  eq('hash /stories', hashFragmentToGoPath('/stories'), '/stories');
  eq('hash #/feed', hashFragmentToGoPath('#/feed'), '/feed');
  eq('hash #/', hashFragmentToGoPath('#/'), null);
  eq('hash #/app', hashFragmentToGoPath('#/app'), null);

  eq(
    'query boot dropped',
    routerQueryFromUri(Uri.parse('https://haneat.app/app/feed?go=1&v=2&_cb=9&fresh=1')),
    null,
  );
  eq(
    'query keeps ref',
    routerQueryFromUri(Uri.parse('https://haneat.app/feed?go=1&ref=alice')),
    'ref=alice',
  );

  FeedShellLaunch.skipReelsTab = true;
  check('skip reels one-shot', FeedShellLaunch.takeSkipReelsTab());
  check('skip reels consumed', !FeedShellLaunch.takeSkipReelsTab());

  if (_failed > 0) {
    // ignore: avoid_print
    print('FAIL $_failed');
    throw StateError('web_app_path checks failed: $_failed');
  }
  // ignore: avoid_print
  print('OK all web_app_path checks');
}
