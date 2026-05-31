import 'package:hive/hive.dart';
import 'recipe.dart';

@HiveType(typeId: 1)
class RecipeModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final int cookTime;
  @HiveField(3)
  final List<String> ingredients;
  @HiveField(4)
  final List<String> steps;
  @HiveField(5)
  final String? image;
  @HiveField(6)
  final DateTime updatedAt;
  @HiveField(7)
  final double? calories;
  @HiveField(8)
  final double? proteinG;
  @HiveField(9)
  final double? carbsG;
  @HiveField(10)
  final double? fatG;

  RecipeModel({
    required this.id,
    required this.title,
    required this.cookTime,
    required this.ingredients,
    required this.steps,
    this.image,
    required this.updatedAt,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  bool get hasNutrition =>
      (calories != null && calories! > 0) ||
      (proteinG != null && proteinG! > 0) ||
      (carbsG != null && carbsG! > 0) ||
      (fatG != null && fatG! > 0);

  static double? parseOptionalDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory RecipeModel.fromMap(Map<String, dynamic> m) => RecipeModel(
        id: m['id'] as String,
        title: m['title'] as String,
        cookTime: m['cookTime'] as int,
        ingredients: List<String>.from(m['ingredients'] as List<dynamic>),
        steps: List<String>.from(m['steps'] as List<dynamic>),
        image: m['image'] as String?,
        updatedAt: m['updatedAt'] != null
            ? DateTime.parse(m['updatedAt'] as String)
            : DateTime.now(),
        calories: parseOptionalDouble(m['calories']),
        proteinG: parseOptionalDouble(m['protein_g']),
        carbsG: parseOptionalDouble(m['carbs_g']),
        fatG: parseOptionalDouble(m['fat_g']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cookTime': cookTime,
        'ingredients': ingredients,
        'steps': steps,
        'image': image,
        'updatedAt': updatedAt.toIso8601String(),
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'protein_g': proteinG,
        if (carbsG != null) 'carbs_g': carbsG,
        if (fatG != null) 'fat_g': fatG,
      };
}

// Manual TypeAdapter so build_runner is not required.
class RecipeModelAdapter extends TypeAdapter<RecipeModel> {
  @override
  final int typeId = 1;

  @override
  RecipeModel read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final cookTime = reader.readInt();
    final ingredients = reader.readList().cast<String>();
    final steps = reader.readList().cast<String>();
    final hasImage = reader.readBool();
    final image = hasImage ? reader.readString() : null;
    final updatedAtMillis = reader.readInt();
    double? calories;
    double? proteinG;
    double? carbsG;
    double? fatG;
    try {
      final marker = reader.readByte();
      if (marker == 1) {
        calories = reader.readDouble();
        proteinG = reader.readDouble();
        carbsG = reader.readDouble();
        fatG = reader.readDouble();
      }
    } catch (_) {
      // Запись без блока КБЖУ (старый формат).
    }
    return RecipeModel(
      id: id,
      title: title,
      cookTime: cookTime,
      ingredients: ingredients,
      steps: steps,
      image: image,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
    );
  }

  @override
  void write(BinaryWriter writer, RecipeModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeInt(obj.cookTime);
    writer.writeList(obj.ingredients);
    writer.writeList(obj.steps);
    if (obj.image != null) {
      writer.writeBool(true);
      writer.writeString(obj.image!);
    } else {
      writer.writeBool(false);
    }
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    if (obj.hasNutrition) {
      writer.writeByte(1);
      writer.writeDouble(obj.calories ?? 0);
      writer.writeDouble(obj.proteinG ?? 0);
      writer.writeDouble(obj.carbsG ?? 0);
      writer.writeDouble(obj.fatG ?? 0);
    }
  }
}

/// Локальная модель [RecipeModel] → [Recipe] для экрана деталей и общих виджетов.
extension RecipeModelAsRecipe on RecipeModel {
  Recipe toRecipe() {
    final numericId = int.tryParse(id);
    final recipeId = numericId ?? id.hashCode & 0x7fffffff;
    final stepMaps = <Map<String, dynamic>>[];
    for (var i = 0; i < steps.length; i++) {
      stepMaps.add({
        'number': i + 1,
        'step': steps[i],
        'image': null,
        'image_url': null,
      });
    }
    Map<String, dynamic>? nutrition;
    if (hasNutrition) {
      nutrition = {
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'protein': proteinG,
        if (carbsG != null) 'carbohydrates': carbsG,
        if (fatG != null) 'fat': fatG,
      };
    }
    return Recipe(
      id: recipeId,
      title: title,
      image: image,
      sourceImage: image,
      usedIngredientCount: ingredients.length,
      ingredients: ingredients,
      steps: stepMaps,
      calories: calories?.round(),
      nutrition: nutrition,
      source: 'local',
    );
  }
}
