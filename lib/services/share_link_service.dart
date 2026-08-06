import '../models/post_model.dart';

class ShareLinkService {
  static const webOrigin = 'https://haneat.app';

  /// Универсальные HTTPS-ссылки: работают в PWA, TWA и браузере.
  static String postLink(int postId) => '$webOrigin/post/$postId';
  static String reelLink(int postId) => '$webOrigin/reel/$postId';
  static String channelLink(int channelId) => '$webOrigin/channel/$channelId';
  static String chatLink(int conversationId, {int? messageId}) {
    final base = '$webOrigin/chats/thread/$conversationId';
    if (messageId == null || messageId <= 0) return base;
    return '$base?msg=$messageId';
  }

  static String profileLink(int userId) => '$webOrigin/profile?userId=$userId';

  static String usernameLink(String username) {
    final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
    return '$webOrigin/u/${Uri.encodeComponent(handle)}';
  }

  static String profileShareText({
    required int userId,
    String? displayName,
    String? username,
  }) {
    final name = (displayName ?? '').trim();
    final handle = (username ?? '').trim().replaceFirst(RegExp(r'^@'), '');
    final title = name.isNotEmpty
        ? name
        : (handle.isNotEmpty ? '@$handle' : 'Профиль');
    final handleLine = handle.isNotEmpty ? '\n@$handle' : '';
    final link =
        handle.isNotEmpty ? usernameLink(handle) : profileLink(userId);
    return '$title$handleLine\n\nОткрыть в HanWe: $link';
  }

  /// Deep link для нативного приложения (не для шаринга наружу).
  static String nativePostLink(int postId) => 'haneat://post/$postId';
  static String nativeChatLink(int conversationId, {int? messageId}) {
    final base = 'haneat://chat/$conversationId';
    if (messageId == null || messageId <= 0) return base;
    return '$base?msg=$messageId';
  }

  static String channelShareText(int channelId, String channelName) {
    final title = channelName.trim().isEmpty ? 'Канал' : channelName.trim();
    return '$title\n\nОткрыть в HanWe: ${channelLink(channelId)}';
  }

  static String postShareText(PostModel post) {
    final title = (post.title ?? post.description ?? 'Пост').trim();
    return '$title\n\nОткрыть в HanWe: ${postLink(post.id)}';
  }

  static String reelShareText(PostModel reel) {
    final title = (reel.title ?? reel.description ?? 'Рилс').trim();
    return '$title\n\nОткрыть в HanWe: ${reelLink(reel.id)}';
  }
}
