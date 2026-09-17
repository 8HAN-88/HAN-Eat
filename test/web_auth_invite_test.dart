import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/auth_route_paths.dart';
import 'package:han_eat/app/web_auth_app.dart';

void main() {
  test('web auth shell opens register when the invite is in the URL', () {
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/app/invite?ref=ABC12XYZ'),
      ),
      AuthPaths.registerWithRef('ABC12XYZ'),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/invite/ABC12XYZ'),
      ),
      AuthPaths.registerWithRef('ABC12XYZ'),
    );
    expect(
      webAuthInitialLocation(Uri.parse('https://haneat.app/app/')),
      AuthPaths.login,
    );
  });
}
