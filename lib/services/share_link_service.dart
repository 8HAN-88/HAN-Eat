import '../models/post_model.dart';
import '../models/recipe.dart';

class ShareLinkService {
  static const webOrigin = 'https://haneat.app';

  /// Универсальные HTTPS-ссылки: работают в PWA, TWA и браузере.
  static String postLink(int postId) => '$webOrigin/post/$postId';
  static String reelLink(int postId) => '$webOrigin/reel/$postId';
  static String recipeLink(int recipeId) => '$webOrigin/recipe/$recipeId';
  static String channelLink(int channelId) => '$webOrigin/channel/$channelId';

  /// Deep link для нативного приложения (не для шаринга наружу).
  static String nativePostLink(int postId) => 'haneat://post/$postId';
  static String nativeRecipeLink(int recipeId) => 'haneat://recipe/$recipeId';

  static String channelShareText(int channelId, String channelName) {
    final title = channelName.trim().isEmpty ? 'Канал' : channelName.trim();
    return '$title\n\nОткрыть в H.A.N. Eat: ${channelLink(channelId)}';
  }

  static String postShareText(PostModel post) {
    final title = (post.title ?? post.description ?? 'Пост').trim();
    return '$title\n\nОткрыть в H.A.N. Eat: ${postLink(post.id)}';
  }

  static String reelShareText(PostModel reel) {
    final title = (reel.title ?? reel.description ?? 'Рилс').trim();
    return '$title\n\nОткрыть в H.A.N. Eat: ${reelLink(reel.id)}';
  }

  static String recipeShareText(Recipe recipe) {
    final title = (recipe.translatedTitle ?? recipe.title).trim();
    return '$title\n\nОткрыть в H.A.N. Eat: ${recipeLink(recipe.id)}';
  }
}
