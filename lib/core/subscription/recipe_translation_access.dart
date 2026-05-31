import '../../models/recipe.dart';
import '../../services/subscription_service.dart';

/// Перевод рецептов Spoonacular на язык из настроек — тариф AI / Pro.
class RecipeTranslationAccess {
  RecipeTranslationAccess._();

  static bool fromSubscription(SubscriptionStatusResponse? status) {
    if (status == null) return false;
    if (!status.isActive && !status.inGracePeriod) return false;
    return status.hasAi;
  }

  static bool localeExpectsTranslation(String languageCode) {
    final lang = languageCode.toLowerCase();
    return lang.startsWith('ru') ||
        lang.startsWith('uk') ||
        lang.startsWith('be') ||
        lang.startsWith('kk');
  }

  static bool _hasCyrillic(String text) {
    return RegExp(r'[\u0400-\u04FF]').hasMatch(text);
  }

  /// Spoonacular-карточки без кириллицы в названии при целевом RU/UK.
  static bool textLooksUntranslated(String text, String languageCode) {
    if (!localeExpectsTranslation(languageCode)) return false;
    final t = text.trim();
    if (t.isEmpty) return false;
    return !_hasCyrillic(t);
  }

  static bool ingredientsLookUntranslated(
    List<String> ingredients,
    String languageCode,
  ) {
    if (ingredients.isEmpty) return false;
    return textLooksUntranslated(ingredients.join(' '), languageCode);
  }

  static bool stepsLookUntranslated(
    List<Map<String, dynamic>> steps,
    String languageCode,
  ) {
    if (steps.isEmpty) return false;
    final buf = StringBuffer();
    for (final s in steps) {
      buf.write(
        s['step'] ?? s['text'] ?? s['instruction'] ?? '',
      );
      buf.write(' ');
    }
    return textLooksUntranslated(buf.toString(), languageCode);
  }

  static bool recipesLookUntranslated(
    List<Recipe> recipes,
    String languageCode,
  ) {
    if (!localeExpectsTranslation(languageCode)) return false;
    var spoonacular = 0;
    var untranslated = 0;
    for (final r in recipes) {
      if (r.source != 'spoonacular') continue;
      spoonacular++;
      final title = (r.translatedTitle?.trim().isNotEmpty == true
              ? r.translatedTitle!
              : r.title)
          .trim();
      if (title.isEmpty || !_hasCyrillic(title)) untranslated++;
    }
    return spoonacular > 0 && untranslated > 0;
  }
}
