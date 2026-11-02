import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/auth_route_paths.dart';
import 'package:han_eat/app/web_auth_location.dart';

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

  test('web auth shell opens forgot / verify / reset from the HTML gate', () {
    expect(
      webAuthInitialLocation(
        Uri.parse(
          'http://127.0.0.1:8088/forgot-password?flutter=1&email=user@test.local',
        ),
      ),
      AuthPaths.forgotPasswordWithEmail('user@test.local'),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse(
          'https://haneat.app/app/verify-email?flutter=1&email=user@test.local&token=123456',
        ),
      ),
      AuthPaths.verifyEmailWith(email: 'user@test.local', token: '123456'),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse(
          'https://haneat.app/app/reset-password?email=user@test.local',
        ),
      ),
      AuthPaths.resetPasswordWith(email: 'user@test.local'),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse(
          'https://haneat.app/app/#/confirm-email-change?email=new@test.local',
        ),
      ),
      AuthPaths.confirmEmailChangeWith(email: 'new@test.local'),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/app/#/registration'),
      ),
      AuthPaths.register,
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/app/#/create-account'),
      ),
      AuthPaths.register,
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/#/forgot'),
      ),
      AuthPaths.forgotPassword,
    );
    expect(
      webAuthInitialLocation(
        Uri.parse(
          'https://haneat.app/app/#/resetpassword?token=654321&email=user@test.local',
        ),
      ),
      AuthPaths.resetPasswordWith(
        token: '654321',
        email: 'user@test.local',
      ),
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/app/#/2fa'),
      ),
      AuthPaths.twoFactorVerify,
    );
    expect(
      webAuthInitialLocation(
        Uri.parse('https://haneat.app/app/#/otp'),
      ),
      AuthPaths.login,
    );
  });
}
