/// Lightweight auth route constants.
///
/// Kept free of screen/router imports so web can ship a small auth boot bundle
/// without pulling WebRTC / InAppWebView / reels into the first JS download.
abstract final class AuthPaths {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const verifyEmail = '/verify-email';
  static const twoFactorVerify = '/2fa-verify';
  static const confirmEmailChange = '/confirm-email-change';
  static const legalConsent = '/legal-consent';
  static const feed = '/feed';
  static const menu = '/';

  static String registerWithRef(String ref) =>
      '$register?ref=${Uri.encodeComponent(ref)}';

  static String forgotPasswordWithEmail(String email) =>
      '$forgotPassword?email=${Uri.encodeComponent(email)}';

  static String verifyEmailWithEmail(String email) =>
      '$verifyEmail?email=${Uri.encodeComponent(email)}';

  static String resetPasswordWith({String? email, String? token}) =>
      _withAuthCode(resetPassword, email: email, token: token);

  static String confirmEmailChangeWith({String? email, String? token}) =>
      _withAuthCode(confirmEmailChange, email: email, token: token);

  static String verifyEmailWith({String? email, String? token}) =>
      _withAuthCode(verifyEmail, email: email, token: token);

  static String _withAuthCode(
    String path, {
    String? email,
    String? token,
  }) {
    return Uri(
      path: path,
      queryParameters: {
        if (token != null && token.isNotEmpty) 'token': token,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    ).toString();
  }
}
