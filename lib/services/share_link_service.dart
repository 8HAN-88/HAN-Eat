import '../models/post_model.dart';
import '../models/recipe.dart';

class ShareLinkService {
  static String postLink(int postId) => 'haneat://post/$postId';
  static String reelLink(int postId) => 'haneat://reel/$postId';
  static String recipeLink(int recipeId) => 'haneat://recipe/$recipeId';
  static String channelLink(int channelId) => 'haneat://channel/$channelId';

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
