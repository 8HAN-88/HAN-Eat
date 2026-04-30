import 'dart:convert';
import 'package:hive/hive.dart';

enum RecipeCategory {
  healthy, // ЗОЖ
  cheap, // Дешево
  lowFat, // Минус жир
  quick, // Быстрое
  vegetarian, // Вегетарианское
  vegan, // Веганское
  glutenFree, // Без глютена
  dairyFree, // Без молока
  lowCarb, // Низкоуглеводное
  highProtein, // Высокобелковое
  dessert, // Десерт
  breakfast, // Завтрак
  lunch, // Обед
  dinner, // Ужин
  snack, // Перекус
  italian, // Итальянская
  asian, // Азиатская
  mexican, // Мексиканская
  mediterranean, // Средиземноморская
  french, // Французская
  japanese, // Японская
  chinese, // Китайская
  indian, // Индийская
  thai, // Тайская
  greek, // Греческая
  spanish, // Испанская
  german, // Немецкая
  russian, // Русская
  american, // Американская
  british, // Британская
  turkish, // Турецкая
  korean, // Корейская
  vietnamese, // Вьетнамская
  brazilian, // Бразильская
  middleEastern, // Ближневосточная
}

extension RecipeCategoryX on RecipeCategory {
  String get displayName {
    switch (this) {
      case RecipeCategory.healthy:
        return 'ЗОЖ';
      case RecipeCategory.cheap:
        return 'Дешево';
      case RecipeCategory.lowFat:
        return 'Минус жир';
      case RecipeCategory.quick:
        return 'Быстрое';
      case RecipeCategory.vegetarian:
        return 'Вегетарианское';
      case RecipeCategory.vegan:
        return 'Веганское';
      case RecipeCategory.glutenFree:
        return 'Без глютена';
      case RecipeCategory.dairyFree:
        return 'Без молока';
      case RecipeCategory.lowCarb:
        return 'Низкоуглеводное';
      case RecipeCategory.highProtein:
        return 'Высокобелковое';
      case RecipeCategory.dessert:
        return 'Десерт';
      case RecipeCategory.breakfast:
        return 'Завтрак';
      case RecipeCategory.lunch:
        return 'Обед';
      case RecipeCategory.dinner:
        return 'Ужин';
      case RecipeCategory.snack:
        return 'Перекус';
      case RecipeCategory.italian:
        return 'Итальянская';
      case RecipeCategory.asian:
        return 'Азиатская';
      case RecipeCategory.mexican:
        return 'Мексиканская';
      case RecipeCategory.mediterranean:
        return 'Средиземноморская';
      case RecipeCategory.french:
        return 'Французская';
      case RecipeCategory.japanese:
        return 'Японская';
      case RecipeCategory.chinese:
        return 'Китайская';
      case RecipeCategory.indian:
        return 'Индийская';
      case RecipeCategory.thai:
        return 'Тайская';
      case RecipeCategory.greek:
        return 'Греческая';
      case RecipeCategory.spanish:
        return 'Испанская';
      case RecipeCategory.german:
        return 'Немецкая';
      case RecipeCategory.russian:
        return 'Русская';
      case RecipeCategory.american:
        return 'Американская';
      case RecipeCategory.british:
        return 'Британская';
      case RecipeCategory.turkish:
        return 'Турецкая';
      case RecipeCategory.korean:
        return 'Корейская';
      case RecipeCategory.vietnamese:
        return 'Вьетнамская';
      case RecipeCategory.brazilian:
        return 'Бразильская';
      case RecipeCategory.middleEastern:
        return 'Ближневосточная';
    }
  }

  String get description {
    switch (this) {
      case RecipeCategory.healthy:
        return 'Здоровые и полезные рецепты';
      case RecipeCategory.cheap:
        return 'Бюджетные рецепты';
      case RecipeCategory.lowFat:
        return 'Низкожировые рецепты';
      case RecipeCategory.quick:
        return 'Быстрые рецепты (до 30 минут)';
      case RecipeCategory.vegetarian:
        return 'Без мяса';
      case RecipeCategory.vegan:
        return 'Без продуктов животного происхождения';
      case RecipeCategory.glutenFree:
        return 'Без глютена';
      case RecipeCategory.dairyFree:
        return 'Без молочных продуктов';
      case RecipeCategory.lowCarb:
        return 'Низкоуглеводные рецепты';
      case RecipeCategory.highProtein:
        return 'Высокобелковые рецепты';
      case RecipeCategory.dessert:
        return 'Десерты и сладости';
      case RecipeCategory.breakfast:
        return 'Рецепты для завтрака';
      case RecipeCategory.lunch:
        return 'Рецепты для обеда';
      case RecipeCategory.dinner:
        return 'Рецепты для ужина';
      case RecipeCategory.snack:
        return 'Перекусы';
      case RecipeCategory.italian:
        return 'Итальянская кухня';
      case RecipeCategory.asian:
        return 'Азиатская кухня';
      case RecipeCategory.mexican:
        return 'Мексиканская кухня';
      case RecipeCategory.mediterranean:
        return 'Средиземноморская кухня';
      case RecipeCategory.french:
        return 'Французская кухня';
      case RecipeCategory.japanese:
        return 'Японская кухня';
      case RecipeCategory.chinese:
        return 'Китайская кухня';
      case RecipeCategory.indian:
        return 'Индийская кухня';
      case RecipeCategory.thai:
        return 'Тайская кухня';
      case RecipeCategory.greek:
        return 'Греческая кухня';
      case RecipeCategory.spanish:
        return 'Испанская кухня';
      case RecipeCategory.german:
        return 'Немецкая кухня';
      case RecipeCategory.russian:
        return 'Русская кухня';
      case RecipeCategory.american:
        return 'Американская кухня';
      case RecipeCategory.british:
        return 'Британская кухня';
      case RecipeCategory.turkish:
        return 'Турецкая кухня';
      case RecipeCategory.korean:
        return 'Корейская кухня';
      case RecipeCategory.vietnamese:
        return 'Вьетнамская кухня';
      case RecipeCategory.brazilian:
        return 'Бразильская кухня';
      case RecipeCategory.middleEastern:
        return 'Ближневосточная кухня';
    }
  }

  String get iconName {
    switch (this) {
      case RecipeCategory.healthy:
        return 'favorite';
      case RecipeCategory.cheap:
        return 'attach_money';
      case RecipeCategory.lowFat:
        return 'water_drop';
      case RecipeCategory.quick:
        return 'schedule';
      case RecipeCategory.vegetarian:
        return 'eco';
      case RecipeCategory.vegan:
        return 'spa';
      case RecipeCategory.glutenFree:
        return 'grain';
      case RecipeCategory.dairyFree:
        return 'no_food';
      case RecipeCategory.lowCarb:
        return 'fitness_center';
      case RecipeCategory.highProtein:
        return 'local_fire_department';
      case RecipeCategory.dessert:
        return 'cake';
      case RecipeCategory.breakfast:
        return 'breakfast_dining';
      case RecipeCategory.lunch:
        return 'lunch_dining';
      case RecipeCategory.dinner:
        return 'dinner_dining';
      case RecipeCategory.snack:
        return 'cookie';
      case RecipeCategory.italian:
        return 'dinner_dining'; // Паста, пицца
      case RecipeCategory.asian:
        return 'ramen_dining'; // Рамен
      case RecipeCategory.mexican:
        return 'local_dining'; // Тако, буррито
      case RecipeCategory.mediterranean:
        return 'set_meal'; // Средиземноморская еда
      case RecipeCategory.french:
        return 'wine_bar'; // Вино и изысканная кухня
      case RecipeCategory.japanese:
        return 'rice_bowl'; // Суши, рис
      case RecipeCategory.chinese:
        return 'takeout_dining'; // Китайская еда на вынос
      case RecipeCategory.indian:
        return 'spicy'; // Острая индийская еда
      case RecipeCategory.thai:
        return 'eco'; // Тайская кухня (зеленая)
      case RecipeCategory.greek:
        return 'circle'; // Оливки (круг)
      case RecipeCategory.spanish:
        return 'tapas'; // Тапас
      case RecipeCategory.german:
        return 'sports_bar'; // Колбасы, пиво
      case RecipeCategory.russian:
        return 'soup_kitchen'; // Супы, борщ
      case RecipeCategory.american:
        return 'fastfood'; // Фастфуд
      case RecipeCategory.british:
        return 'lunch_dining'; // Рыба и чипсы
      case RecipeCategory.turkish:
        return 'kebab'; // Кебаб
      case RecipeCategory.korean:
        return 'breakfast_dining'; // Корейская кухня
      case RecipeCategory.vietnamese:
        return 'cookie'; // Вьетнамская кухня
      case RecipeCategory.brazilian:
        return 'outdoor_grill'; // Бразильское барбекю
      case RecipeCategory.middleEastern:
        return 'cake'; // Ближневосточная кухня
    }
  }

  /// Теги для Spoonacular API
  String get spoonacularTag {
    switch (this) {
      case RecipeCategory.healthy:
        return 'healthy';
      case RecipeCategory.cheap:
        return 'cheap';
      case RecipeCategory.lowFat:
        return 'low-fat';
      case RecipeCategory.quick:
        return 'quick';
      case RecipeCategory.vegetarian:
        return 'vegetarian';
      case RecipeCategory.vegan:
        return 'vegan';
      case RecipeCategory.glutenFree:
        return 'gluten-free';
      case RecipeCategory.dairyFree:
        return 'dairy-free';
      case RecipeCategory.lowCarb:
        return 'low-carb';
      case RecipeCategory.highProtein:
        return 'high-protein';
      case RecipeCategory.dessert:
        return 'dessert';
      case RecipeCategory.breakfast:
        return 'breakfast';
      case RecipeCategory.lunch:
        return 'lunch';
      case RecipeCategory.dinner:
        return 'dinner';
      case RecipeCategory.snack:
        return 'snack';
      case RecipeCategory.italian:
        return 'italian';
      case RecipeCategory.asian:
        return 'asian';
      case RecipeCategory.mexican:
        return 'mexican';
      case RecipeCategory.mediterranean:
        return 'mediterranean';
      case RecipeCategory.french:
        return 'french';
      case RecipeCategory.japanese:
        return 'japanese';
      case RecipeCategory.chinese:
        return 'chinese';
      case RecipeCategory.indian:
        return 'indian';
      case RecipeCategory.thai:
        return 'thai';
      case RecipeCategory.greek:
        return 'greek';
      case RecipeCategory.spanish:
        return 'spanish';
      case RecipeCategory.german:
        return 'german';
      case RecipeCategory.russian:
        return 'russian';
      case RecipeCategory.american:
        return 'american';
      case RecipeCategory.british:
        return 'british';
      case RecipeCategory.turkish:
        return 'turkish';
      case RecipeCategory.korean:
        return 'korean';
      case RecipeCategory.vietnamese:
        return 'vietnamese';
      case RecipeCategory.brazilian:
        return 'brazilian';
      case RecipeCategory.middleEastern:
        return 'middle-eastern';
    }
  }

  CategoryType get type {
    if ([
      RecipeCategory.healthy,
      RecipeCategory.cheap,
      RecipeCategory.lowFat,
      RecipeCategory.quick,
    ].contains(this)) {
      return CategoryType.practical;
    }
    if ([
      RecipeCategory.vegetarian,
      RecipeCategory.vegan,
      RecipeCategory.glutenFree,
      RecipeCategory.dairyFree,
      RecipeCategory.lowCarb,
      RecipeCategory.highProtein,
    ].contains(this)) {
      return CategoryType.dietary;
    }
    if ([
      RecipeCategory.breakfast,
      RecipeCategory.lunch,
      RecipeCategory.dinner,
      RecipeCategory.snack,
      RecipeCategory.dessert,
    ].contains(this)) {
      return CategoryType.mealType;
    }
    return CategoryType.cuisine;
  }

  String get color {
    switch (this.type) {
      case CategoryType.practical:
        return 'blue';
      case CategoryType.dietary:
        return 'green';
      case CategoryType.mealType:
        return 'orange';
      case CategoryType.cuisine:
        return 'purple';
    }
  }
}

enum CategoryType {
  practical, // Практические (ЗОЖ, Дешево, Быстро)
  dietary, // Диетические (Веган, Без глютена)
  mealType, // Тип приема пищи
  cuisine, // Кухня
}

class CategoryFilter {
  final RecipeCategory category;
  final bool isActive;
  final int priority; // Для сортировки

  CategoryFilter({
    required this.category,
    this.isActive = false,
    this.priority = 0,
  });

  CategoryFilter copyWith({
    RecipeCategory? category,
    bool? isActive,
    int? priority,
  }) {
    return CategoryFilter(
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category.index,
      'isActive': isActive,
      'priority': priority,
    };
  }

  factory CategoryFilter.fromJson(Map<String, dynamic> json) {
    return CategoryFilter(
      category: RecipeCategory.values[json['category'] as int],
      isActive: json['isActive'] as bool? ?? false,
      priority: json['priority'] as int? ?? 0,
    );
  }
}

// Manual TypeAdapters (no build_runner needed)
class RecipeCategoryAdapter extends TypeAdapter<RecipeCategory> {
  @override
  final int typeId = 5;

  @override
  RecipeCategory read(BinaryReader reader) {
    return RecipeCategory.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, RecipeCategory obj) {
    writer.writeByte(obj.index);
  }
}

class CategoryFilterAdapter extends TypeAdapter<CategoryFilter> {
  @override
  final int typeId = 6;

  @override
  CategoryFilter read(BinaryReader reader) {
    final jsonString = reader.readString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CategoryFilter.fromJson(json);
  }

  @override
  void write(BinaryWriter writer, CategoryFilter obj) {
    final jsonString = jsonEncode(obj.toJson());
    writer.writeString(jsonString);
  }
}

