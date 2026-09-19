import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/auth/otp_code.dart';
import 'package:han_eat/features/auth/presentation/reset_password_screen.dart';
import 'package:han_eat/features/auth/presentation/two_factor_verify_screen.dart';
import 'package:han_eat/features/auth/presentation/verify_email_screen.dart';
import 'package:han_eat/widgets/otp_code_input.dart';

void main() {
  test('otp helpers accept spaced six digits and legacy tokens', () {
    expect(isOtpCode('123456'), isTrue);
    expect(isOtpCode('123 456'), isTrue);
    expect(isOtpCode('12-34-56'), isTrue);
    expect(isOtpCode('12345'), isFalse);
    expect(isLegacyAuthToken('short'), isFalse);
    expect(
      isLegacyAuthToken('abcdefghijklmnop'),
      isTrue,
    );
    expect(
      normalizeOtpInput('abcde-fghij-klmno-pqrstu'),
      'abcde-fghij-klmno-pqrstu',
    );
    expect(
      resolveAuthCode(
        typed: '',
        linkToken: 'abcde-fghij-klmno-pqrstu',
      ),
      'abcde-fghij-klmno-pqrstu',
    );
  });

  testWidgets('digit boxes complete after six numbers', (tester) async {
    String? completed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpCodeInput(
            onCompleted: (code) => completed = code,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(completed, '123456');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('verify email asks for a six-digit code', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifyEmailScreen(email: 'user@test.local'),
      ),
    );
    await tester.pump();
    expect(find.text('Подтверждение почты'), findsOneWidget);
    expect(find.text('Введите код из письма'), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(find.text('Код из письма'), findsNothing);
  });

  testWidgets('reset password shows digit boxes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResetPasswordScreen(initialEmail: 'user@test.local'),
      ),
    );
    await tester.pump();
    expect(find.text('Новый пароль'), findsWidgets);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    await tester.enterText(
        find.descendant(
          of: find.byType(OtpCodeInput),
          matching: find.byType(TextField),
        ),
        '654321');
    await tester.pump();
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Вставьте токен'), findsNothing);
  });

  testWidgets('two-factor login shows digit boxes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TwoFactorVerifyScreen(
          pendingToken: 'pending-token-at-least-16',
          email: 'user@test.local',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Код подтверждения'), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(find.text('Введите 6 цифр'), findsNothing);
  });
}
