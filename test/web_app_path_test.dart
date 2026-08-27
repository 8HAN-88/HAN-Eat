import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/web_app_path.dart';

void main() {
  group('isWebAppShellPath', () {
    test('treats PWA mount as the HTML shell', () {
      expect(isWebAppShellPath('/app'), isTrue);
      expect(isWebAppShellPath('/app/'), isTrue);
      expect(isWebAppShellPath('/app/index.html'), isTrue);
    });

    test('does not treat real app routes as the shell', () {
      expect(isWebAppShellPath('/feed'), isFalse);
      expect(isWebAppShellPath('/app/feed'), isFalse);
      expect(isWebAppShellPath('/'), isFalse);
    });
  });

  group('browserPathToGoPath', () {
    test('PWA shell is not a GoRouter location', () {
      expect(browserPathToGoPath('/app'), isNull);
      expect(browserPathToGoPath('/app/'), isNull);
      expect(browserPathToGoPath('/app/index.html'), isNull);
      expect(browserPathToGoPath('/'), isNull);
      expect(browserPathToGoPath(''), isNull);
    });

    test('strips /app prefix from real routes', () {
      expect(browserPathToGoPath('/app/feed'), '/feed');
      expect(browserPathToGoPath('/app/feed/'), '/feed');
      expect(browserPathToGoPath('/app/@alice'), '/@alice');
      expect(browserPathToGoPath('/app/chats/thread/1'), '/chats/thread/1');
    });

    test('leaves ordinary deep-link paths unchanged', () {
      expect(browserPathToGoPath('/feed'), '/feed');
      expect(browserPathToGoPath('/post/12'), '/post/12');
      expect(browserPathToGoPath('/@bob'), '/@bob');
    });
  });
}
