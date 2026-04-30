// lib/models/recipe.dart

class Recipe {
  final int id;
  final String title;
  final String? image;
  final String? sourceImage;
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
  final String? source; // "spoonacular" или "user" - источник рецепта
  final String? authorAvatar; // Аватарка автора
  final double? rating; // Рейтинг рецепта (0-5)
  final int? likesCount; // Количество лайков
  final int? mealPlanCount; // Количество добавлений в план питания
  final int? servings; // Количество порций (для пересчёта ингредиентов)

  Recipe({
    required this.id,
    required this.title,
    this.image,
    this.sourceImage,
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
    this.source,
    this.authorAvatar,
    this.rating,
    this.likesCount,
    this.mealPlanCount,
    this.servings,
  });

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
          final finalImage = (imageStr != null && imageStr.isNotEmpty && imageStr != 'null' && imageStr.trim().isNotEmpty) 
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
      if (idStr.startsWith('user_') || idStr.startsWith('channel_')) {
        // Для рецептов пользователей/каналов используем числовую часть
        final numPart = idStr.replaceFirst(RegExp(r'^(user_|channel_)'), '');
        recipeId = int.tryParse(numPart) ?? 0;
      } else {
        recipeId = int.tryParse(idStr) ?? 0;
      }
    }
    
    // Обрабатываем изображения - убираем пустые строки
    final imageStr = json['image']?.toString();
    final sourceImageStr = json['source_image']?.toString();
    final image = (imageStr != null && imageStr.isNotEmpty) ? imageStr : null;
    final sourceImage = (sourceImageStr != null && sourceImageStr.isNotEmpty) ? sourceImageStr : null;
    
    return Recipe(
      id: recipeId,

      title: json['title']?.toString() ?? '',
      image: image,
      sourceImage: sourceImage,

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
          final finalImage = (imageStr != null && imageStr.isNotEmpty && imageStr != 'null' && imageStr.trim().isNotEmpty) 
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
      calories: json['calories'] is int
          ? json['calories']
          : (json['calories'] is num 
              ? (json['calories'] as num).toInt() 
              : int.tryParse('${json['calories']}')),
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
      author: json['author']?.toString(),
      source: json['source']?.toString(),
      authorAvatar: json['author_avatar']?.toString(),
      rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
      likesCount: json['likes_count'] is int ? json['likes_count'] : (json['likes_count'] is num ? (json['likes_count'] as num).toInt() : null),
      mealPlanCount: json['meal_plan_count'] is int ? json['meal_plan_count'] : (json['meal_plan_count'] is num ? (json['meal_plan_count'] as num).toInt() : null),
      servings: json['servings'] is int ? json['servings'] : (json['servings'] is num ? (json['servings'] as num).toInt() : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'source_image': sourceImage,
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
      'source': source,
      'author_avatar': authorAvatar,
      'rating': rating,
      'likes_count': likesCount,
      'meal_plan_count': mealPlanCount,
      'servings': servings,
    };
  }
}
