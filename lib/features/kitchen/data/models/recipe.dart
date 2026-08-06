// lib/models/recipe.dart
import 'package:han_eat/services/server_config.dart';

const Object _copyWithSentinel = Object();

class Recipe {
  final int id;
  final String title;
  final String? image;
  final String? sourceImage;
  final List<String> imageUrls;
  final int usedIngredientCount;

  /// Список ингредиентов всегда строковый
  final List<String> ingredients;

  /// Steps — список карт: number, step, image
  final List<Map<String, dynamic>> steps;
  final String? translatedTitle;
  final List<String>? translatedIngredients;
  final List<Map<String, dynamic>>? translatedSteps;
  final int? calories;
  final Map<String, dynamic>? nutrition;
  final String? summary;
  final String? mode;
  final String? sourceLanguage;
  final String? targetLanguage;
  final String? videoUrl;
  final String? videoThumbnail;
  final String? author; // Для рецептов пользователей
  final int? authorId; // ID автора для подписки и перехода в профиль
  final int? channelId; // Канал-источник рецепта
  final String? source; // "spoonacular" | "user" | "channel"
  final String? authorAvatar; // Аватарка автора
  final double? rating; // Рейтинг рецепта (0-5)
  final int? likesCount; // Количество лайков
  final int? commentsCount; // Количество комментариев
  final int? ratingCount; // Количество оценок
  final int? mealPlanCount; // Количество добавлений в план питания
  final int? servings; // Количество порций (для пересчёта ингредиентов)
  final double? qualityScore; // Качество карточки в Menu
  final double? relevanceScore; // Релевантность запросу/фильтрам
  final String? reasonLabel; // Почему рецепт показан
  final String? sourceLabel; // Человекочитаемый источник
  final String? menuSection; // Секция витрины Menu
  final String? originCountryCode; // ISO 3166-1 alpha-2 — страна/кухня блюда
  final String? originCountryName;

  /// Граммы макронутриента из [nutrition] (Spoonacular `nutrients` или плоские ключи).
  double? nutrientGrams(String name) {
    final n = nutrition;
    if (n == null) return null;
    final nutrients = n['nutrients'];
    if (nutrients is List) {
      for (final raw in nutrients) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if ('${m['name']}'.toLowerCase() == name.toLowerCase()) {
          final amt = m['amount'];
          if (amt is num) return amt.toDouble();
          return double.tryParse('$amt');
        }
      }
    }
    final key = name.toLowerCase();
    final direct = n[key] ?? n[name];
    if (direct is num) return direct.toDouble();
    if (direct is String) {
      return double.tryParse(
        direct.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '.'),
      );
    }
    return null;
  }

  Recipe({
    required this.id,
    required this.title,
    this.image,
    this.sourceImage,
    List<String>? imageUrls,
    required this.usedIngredientCount,
    required this.ingredients,
    required this.steps,
    this.translatedTitle,
    this.translatedIngredients,
    this.translatedSteps,
    this.calories,
    this.nutrition,
    this.summary,
    this.mode,
    this.sourceLanguage,
    this.targetLanguage,
    this.videoUrl,
    this.videoThumbnail,
    this.author,
    this.authorId,
    this.channelId,
    this.source,
    this.authorAvatar,
    this.rating,
    this.likesCount,
    this.commentsCount,
    this.ratingCount,
    this.mealPlanCount,
    this.servings,
    this.qualityScore,
    this.relevanceScore,
    this.reasonLabel,
    this.sourceLabel,
    this.menuSection,
    this.originCountryCode,
    this.originCountryName,
  }) : imageUrls = imageUrls ?? _dedupeImageUrls([image, sourceImage]);

  String? get originCountryLabel {
    final code = originCountryCode?.trim();
    if (code == null || code.isEmpty) return originCountryName;
    return originCountryName != null && originCountryName!.isNotEmpty
        ? originCountryName
        : code;
  }

  Recipe copyWith({
    Object? image = _copyWithSentinel,
    Object? sourceImage = _copyWithSentinel,
    List<String>? imageUrls,
  }) {
    return Recipe(
      id: id,
      title: title,
      image:
          identical(image, _copyWithSentinel) ? this.image : image as String?,
      sourceImage: identical(sourceImage, _copyWithSentinel)
          ? this.sourceImage
          : sourceImage as String?,
      imageUrls: imageUrls ?? this.imageUrls,
      usedIngredientCount: usedIngredientCount,
      ingredients: ingredients,
      steps: steps,
      translatedTitle: translatedTitle,
      translatedIngredients: translatedIngredients,
      translatedSteps: translatedSteps,
      calories: calories,
      nutrition: nutrition,
      summary: summary,
      mode: mode,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      videoUrl: videoUrl,
      videoThumbnail: videoThumbnail,
      author: author,
      authorId: authorId,
      channelId: channelId,
      source: source,
      authorAvatar: authorAvatar,
      rating: rating,
      likesCount: likesCount,
      commentsCount: commentsCount,
      ratingCount: ratingCount,
      mealPlanCount: mealPlanCount,
      servings: servings,
      qualityScore: qualityScore,
      relevanceScore: relevanceScore,
      reasonLabel: reasonLabel,
      sourceLabel: sourceLabel,
      menuSection: menuSection,
      originCountryCode: originCountryCode,
      originCountryName: originCountryName,
    );
  }

  static String? _nonEmptyStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  static List<String> _dedupeImageUrls(Iterable<dynamic> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final s = _nonEmptyStr(value);
      if (s == null || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }

  static List<String> _imageUrlsFromJson(Map<String, dynamic> json) {
    final urls = <dynamic>[
      json['image'],
      json['source_image'],
      json['image_url'],
      json['thumbnail_url'],
    ];
    final rawImages = json['images'] ?? json['photos'] ?? json['image_urls'];
    if (rawImages is List) {
      urls.addAll(rawImages);
    }
    final rawMedia = json['media'];
    if (rawMedia is List) {
      for (final item in rawMedia) {
        if (item is! Map) continue;
        final type = item['type']?.toString();
        if (type == null || type == 'image') {
          urls.add(item['url'] ?? item['image'] ?? item['image_url']);
        }
      }
    }
    final nested = json['recipe'];
    if (nested is Map) {
      urls.addAll(_imageUrlsFromJson(Map<String, dynamic>.from(nested)));
    }
    return _dedupeImageUrls(urls);
  }

  static int? _intFromJson(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _doubleFromJson(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Recipe fromPostModel(dynamic post) {
    final body = post.body as Map<String, dynamic>? ?? const {};
    final nested = body['recipe'];
    final nestedMap =
        nested is Map ? Map<String, dynamic>.from(nested) : <String, dynamic>{};
    final ingredients = (body['translated_ingredients'] as List<dynamic>?) ??
        (body['ingredients'] as List<dynamic>?) ??
        (nestedMap['ingredients'] as List<dynamic>?) ??
        const [];
    final steps = (body['translated_steps'] as List<dynamic>?) ??
        (body['steps'] as List<dynamic>?) ??
        (nestedMap['steps'] as List<dynamic>?) ??
        const [];
    final title = _nonEmptyStr(post.title) ??
        _nonEmptyStr(body['title']) ??
        _nonEmptyStr(body['translated_title']) ??
        _nonEmptyStr(body['name']) ??
        _nonEmptyStr(nestedMap['title']) ??
        'Рецепт';
    final hasSpoonacularId = body['spoonacular_recipe_id'] != null;
    final rawId = body['spoonacular_recipe_id'] ??
        body['recipe_id'] ??
        nestedMap['id'] ??
        post.id;
    final sourceFromBody = _nonEmptyStr(body['source']);
    final sourceFromNested = _nonEmptyStr(nestedMap['source']);
    final isChannelRecipe = post.channelId != null;
    final source = sourceFromBody ??
        sourceFromNested ??
        (hasSpoonacularId
            ? 'spoonacular'
            : (isChannelRecipe ? 'channel' : 'user'));
    final channelName = post.channel?.name ?? _nonEmptyStr(body['channel_name']);
    final channelAvatar = post.channel?.avatarUrl ??
        _nonEmptyStr(body['channel_avatar']);
    final json = <String, dynamic>{
      ...nestedMap,
      ...body,
      'id': rawId,
      'title': title,
      'ingredients': ingredients,
      'steps': steps,
      'translated_title':
          body['translated_title'] ?? nestedMap['translated_title'],
      'translated_ingredients':
          body['translated_ingredients'] ?? nestedMap['translated_ingredients'],
      'translated_steps':
          body['translated_steps'] ?? nestedMap['translated_steps'],
      'usedIngredientCount': ingredients.length,
      'calories': body['calories'] ?? nestedMap['calories'],
      'nutrition': body['nutrition'] ?? nestedMap['nutrition'],
      'source': source,
      'author': post.author?.name ?? nestedMap['author'] ?? body['author'],
      'author_id': post.userId ?? nestedMap['author_id'] ?? body['author_id'],
      'author_avatar': post.author?.avatarUrl ??
          nestedMap['author_avatar'] ??
          body['author_avatar'],
      'likes_count': post.likesCount,
      'comments_count': post.commentsCount,
      'rating': body['rating'] ?? nestedMap['rating'],
      'rating_count': body['rating_count'] ?? nestedMap['rating_count'],
      'media': body['media'],
      'photos': body['photos'],
      'source_image': body['source_image'] ?? nestedMap['source_image'],
      'image': body['image'] ?? nestedMap['image'],
    };
    final recipe = Recipe.fromJson(json);
    final resolvedUrls =
        recipe.imageUrls.map(ServerConfig.resolveMediaUrl).toList();
    return Recipe(
      id: recipe.id,
      title: recipe.title,
      image: resolvedUrls.isNotEmpty ? resolvedUrls.first : recipe.image,
      sourceImage: recipe.sourceImage,
      imageUrls: resolvedUrls,
      usedIngredientCount: recipe.usedIngredientCount,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      translatedTitle: recipe.translatedTitle,
      translatedIngredients: recipe.translatedIngredients,
      translatedSteps: recipe.translatedSteps,
      calories: recipe.calories,
      nutrition: recipe.nutrition,
      summary: recipe.summary,
      mode: recipe.mode,
      sourceLanguage: recipe.sourceLanguage,
      targetLanguage: recipe.targetLanguage,
      videoUrl: recipe.videoUrl,
      videoThumbnail: recipe.videoThumbnail,
      author: recipe.author,
      authorId: recipe.authorId,
      channelId: recipe.channelId ?? post.channelId,
      source: recipe.source,
      authorAvatar: recipe.authorAvatar,
      rating: recipe.rating,
      likesCount: recipe.likesCount,
      commentsCount: recipe.commentsCount,
      ratingCount: recipe.ratingCount,
      mealPlanCount: recipe.mealPlanCount,
      servings: recipe.servings,
      qualityScore: recipe.qualityScore,
      relevanceScore: recipe.relevanceScore,
      reasonLabel: recipe.reasonLabel,
      sourceLabel: recipe.sourceLabel,
      menuSection: recipe.menuSection,
      originCountryCode: recipe.originCountryCode,
      originCountryName: recipe.originCountryName,
    );
  }

  static String? _authorFromJson(Map<String, dynamic> json) {
    final rawAuthor = json['author'];
    if (rawAuthor is String) {
      return _nonEmptyStr(rawAuthor);
    }
    if (rawAuthor is Map) {
      final m = Map<String, dynamic>.from(rawAuthor);
      return _nonEmptyStr(m['name']) ??
          _nonEmptyStr(m['display_name']) ??
          _nonEmptyStr(m['username']);
    }
    return _nonEmptyStr(json['publisher_name']) ??
        _nonEmptyStr(json['channel_name']);
  }

  static String? _authorAvatarFromJson(Map<String, dynamic> json) {
    final flat = _nonEmptyStr(json['author_avatar']) ??
        _nonEmptyStr(json['authorAvatar']) ??
        _nonEmptyStr(json['avatar_url']) ??
        _nonEmptyStr(json['channel_avatar']) ??
        _nonEmptyStr(json['channel_image_url']) ??
        _nonEmptyStr(json['group_avatar']) ??
        _nonEmptyStr(json['profile_image_url']);
    if (flat != null) return flat;
    final rawAuthor = json['author'];
    if (rawAuthor is Map) {
      final m = Map<String, dynamic>.from(rawAuthor);
      return _nonEmptyStr(m['avatar_url']) ?? _nonEmptyStr(m['avatarUrl']);
    }
    return null;
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    // 1. Парсим ингредиенты надёжно
    final rawIngredients = json['ingredients'];
    List<String> parsedIngredients = [];

    if (rawIngredients is List) {
      parsedIngredients = rawIngredients
          .map((e) => e.toString()) // Приводим всё к String
          .toList();
    }

    // 2. Парсим шаги
    final rawSteps = json['steps'];
    List<Map<String, dynamic>> parsedSteps = [];

    if (rawSteps is List) {
      for (final s in rawSteps) {
        if (s is Map) {
          // Проверяем оба поля для изображения
          final imageValue = s['image'] ?? s['image_url'];
          final imageStr = imageValue != null
              ? (imageValue is String ? imageValue : imageValue.toString())
              : null;
          final finalImage = (imageStr != null &&
                  imageStr.isNotEmpty &&
                  imageStr != 'null' &&
                  imageStr.trim().isNotEmpty)
              ? imageStr.trim()
              : null;
          parsedSteps.add({
            'number': s['number'] ?? (parsedSteps.length + 1),
            'step': s['step'] ?? s['text'] ?? s['instruction'] ?? '',
            'image': finalImage,
            'image_url': finalImage, // Дублируем для совместимости
          });
        } else if (s is String) {
          parsedSteps.add({
            'number': parsedSteps.length + 1,
            'step': s,
            'image': null,
            'image_url': null,
          });
        }
      }
    }

    // Обрабатываем ID: может быть int или строка вида "user_123" или "channel_123"
    int recipeId = 0;
    if (json['id'] is int) {
      recipeId = json['id'] as int;
    } else {
      final idStr = '${json['id']}';
      if (idStr.startsWith('user_') ||
          idStr.startsWith('channel_') ||
          idStr.startsWith('base_') ||
          idStr.startsWith('builtin_')) {
        // Для рецептов пользователей/каналов используем числовую часть
        final numPart =
            idStr.replaceFirst(RegExp(r'^(user_|channel_|base_|builtin_)'), '');
        recipeId = int.tryParse(numPart) ?? 0;
      } else {
        recipeId = int.tryParse(idStr) ?? 0;
      }
    }

    // Обрабатываем изображения - убираем пустые строки
    final imageUrls = _imageUrlsFromJson(json);
    final image = imageUrls.isNotEmpty ? imageUrls.first : null;
    final sourceImage = _nonEmptyStr(json['source_image']) ?? image;

    return Recipe(
      id: recipeId,
      title: json['title']?.toString() ?? '',
      image: image,
      sourceImage: sourceImage,
      imageUrls: imageUrls,
      usedIngredientCount: json['usedIngredientCount'] is int
          ? json['usedIngredientCount']
          : int.tryParse('${json['usedIngredientCount']}') ?? 0,
      ingredients: parsedIngredients,
      steps: parsedSteps,
      translatedTitle: json['translated_title']?.toString(),
      translatedIngredients: (json['translated_ingredients'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      translatedSteps: (json['translated_steps'] as List<dynamic>?)
          ?.asMap()
          .entries
          .map((entry) {
        final idx = entry.key + 1;
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          // Проверяем оба поля для изображения
          final imageValue = value['image'] ?? value['image_url'];
          final imageStr = imageValue != null
              ? (imageValue is String ? imageValue : imageValue.toString())
              : null;
          final finalImage = (imageStr != null &&
                  imageStr.isNotEmpty &&
                  imageStr != 'null' &&
                  imageStr.trim().isNotEmpty)
              ? imageStr.trim()
              : null;
          return {
            'number': value['number'] ?? idx,
            'step': value['step'] ?? value['text'] ?? value['instruction'],
            'image': finalImage,
            'image_url': finalImage, // Дублируем для совместимости
          };
        }
        return {
          'number': idx,
          'step': value.toString(),
          'image': null,
          'image_url': null,
        };
      }).toList(),
      calories: _intFromJson(json['calories']),
      nutrition: json['nutrition'] != null
          ? (json['nutrition'] is Map
              ? Map<String, dynamic>.from(json['nutrition'] as Map)
              : null)
          : null,
      summary: json['summary']?.toString(),
      mode: json['mode']?.toString(),
      sourceLanguage: json['source_language']?.toString(),
      targetLanguage: json['target_language']?.toString(),
      videoUrl: json['video_url']?.toString(),
      videoThumbnail: json['video_thumbnail']?.toString(),
      author: _authorFromJson(json),
      authorId: _intFromJson(
        json['author_id'] ?? json['user_id'] ?? json['publisher_id'],
      ),
      channelId: _intFromJson(json['channel_id']),
      source: _nonEmptyStr(json['source']),
      authorAvatar: _authorAvatarFromJson(json),
      rating: _doubleFromJson(json['rating']),
      likesCount: _intFromJson(json['likes_count'] ?? json['likes']),
      commentsCount: _intFromJson(json['comments_count'] ?? json['comments']),
      ratingCount: _intFromJson(json['rating_count'] ?? json['ratings_count']),
      mealPlanCount: _intFromJson(json['meal_plan_count']),
      servings: _intFromJson(json['servings']),
      qualityScore: _doubleFromJson(json['quality_score']),
      relevanceScore: _doubleFromJson(json['relevance_score']),
      reasonLabel: _nonEmptyStr(json['reason_label']),
      sourceLabel: _nonEmptyStr(json['source_label']),
      menuSection: _nonEmptyStr(json['menu_section']),
      originCountryCode: _nonEmptyStr(json['origin_country_code']),
      originCountryName: _nonEmptyStr(json['origin_country_name']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'source_image': sourceImage,
      'images': imageUrls,
      'usedIngredientCount': usedIngredientCount,
      'ingredients': ingredients,
      'steps': steps,
      'translated_title': translatedTitle,
      'translated_ingredients': translatedIngredients,
      'translated_steps': translatedSteps,
      'calories': calories,
      'nutrition': nutrition,
      'summary': summary,
      'mode': mode,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'video_url': videoUrl,
      'video_thumbnail': videoThumbnail,
      'author': author,
      'author_id': authorId,
      'channel_id': channelId,
      'source': source,
      'author_avatar': authorAvatar,
      'rating': rating,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'rating_count': ratingCount,
      'meal_plan_count': mealPlanCount,
      'servings': servings,
      'quality_score': qualityScore,
      'relevance_score': relevanceScore,
      'reason_label': reasonLabel,
      'source_label': sourceLabel,
      'menu_section': menuSection,
      'origin_country_code': originCountryCode,
      'origin_country_name': originCountryName,
    };
  }
}
