import 'app_build_config.dart';

/// Публичные юридические документы.
///
/// На проде: `https://haneat.app/privacy` и `/terms` (nginx → API).
/// Fallback для dev без nginx: `{apiBaseRoot}/privacy`.
abstract final class LegalUrls {
  static const _publicOrigin = 'https://haneat.app';

  static String get privacyPolicy => AppBuildConfig.isProduction
      ? '$_publicOrigin/privacy'
      : '${AppBuildConfig.apiBaseRoot}/privacy';

  static String get termsOfService => AppBuildConfig.isProduction
      ? '$_publicOrigin/terms'
      : '${AppBuildConfig.apiBaseRoot}/terms';

  static const supportEmail = 'mailto:support@haneat.app';
}
