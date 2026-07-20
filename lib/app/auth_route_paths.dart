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
  static const legalConsent = '/legal-consent';
  static const feed = '/feed';
  static const menu = '/';

  static String forgotPasswordWithEmail(String email) =>
      '$forgotPassword?email=${Uri.encodeComponent(email)}';

  static String verifyEmailWithEmail(String email) =>
      '$verifyEmail?email=${Uri.encodeComponent(email)}';
}
