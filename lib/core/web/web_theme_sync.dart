import 'web_theme_sync_stub.dart'
    if (dart.library.html) 'web_theme_sync_web.dart' as impl;

void syncWebDocumentTheme({required bool isDark}) =>
    impl.syncWebDocumentTheme(isDark: isDark);

void setWebReelSeeThrough(bool enabled) => impl.setWebReelSeeThrough(enabled);
