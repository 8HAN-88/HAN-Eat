import 'app_build_config.dart';

/// Публичные юридические документы.
///
/// HTML отдаёт backend: `{apiBaseRoot}/privacy` и `/terms`.
/// Домен haneat.app — только после прокси в nginx (см. docs/LEGAL_PAGES_DEPLOY.md).
abstract final class LegalUrls {
  static String get privacyPolicy =>
      '${AppBuildConfig.apiBaseRoot}/privacy';

  static String get termsOfService =>
      '${AppBuildConfig.apiBaseRoot}/terms';

  static const supportEmail = 'mailto:support@haneat.app';
}
