import 'dart:convert';
import 'package:hive/hive.dart';
import 'recipe_model.dart';

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack,
}

extension MealTypeX on MealType {
  String get displayName {
    switch (this) {
      case MealType.breakfast:
        return 'Завтрак';
      case MealType.lunch:
        return 'Обед';
      case MealType.dinner:
        return 'Ужин';
      case MealType.snack:
        return 'Перекус';
    }
  }

  String get iconName {
    switch (this) {
      case MealType.breakfast:
        return 'breakfast_dining';
      case MealType.lunch:
        return 'lunch_dining';
      case MealType.dinner:
        return 'dinner_dining';
      case MealType.snack:
        return 'cookie';
    }
  }
}

class MealPlanEntry {
  final String id;
  final RecipeModel recipe;
  final MealType mealType;
  final DateTime date;
  final int servings;
  final DateTime createdAt;

  MealPlanEntry({
    required this.id,
    required this.recipe,
    required this.mealType,
    required this.date,
    this.servings = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  MealPlanEntry copyWith({
    String? id,
    RecipeModel? recipe,
    MealType? mealType,
    DateTime? date,
    int? servings,
    DateTime? createdAt,
  }) {
    return MealPlanEntry(
      id: id ?? this.id,
      recipe: recipe ?? this.recipe,
      mealType: mealType ?? this.mealType,
      date: date ?? this.date,
      servings: servings ?? this.servings,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recipe': recipe.toMap(),
      'mealType': mealType.index,
      'date': date.toIso8601String(),
      'servings': servings,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MealPlanEntry.fromJson(Map<String, dynamic> json) {
    return MealPlanEntry(
      id: json['id'] as String,
      recipe: RecipeModel.fromMap(json['recipe'] as Map<String, dynamic>),
      mealType: MealType.values[json['mealType'] as int],
      date: DateTime.parse(json['date'] as String),
      servings: json['servings'] as int? ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

class DailyMealPlan {
  final DateTime date;
  final List<MealPlanEntry> entries;

  DailyMealPlan({
    required this.date,
    required this.entries,
  });

  DailyMealPlan copyWith({
    DateTime? date,
    List<MealPlanEntry>? entries,
  }) {
    return DailyMealPlan(
      date: date ?? this.date,
      entries: entries ?? this.entries,
    );
  }

  int get totalCalories {
    // Можно расширить для подсчета калорий из рецептов
    return 0;
  }

  List<MealPlanEntry> getEntriesForMeal(MealType mealType) {
    return entries.where((e) => e.mealType == mealType).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  factory DailyMealPlan.fromJson(Map<String, dynamic> json) {
    return DailyMealPlan(
      date: DateTime.parse(json['date'] as String),
      entries: (json['entries'] as List<dynamic>)
          .map((e) => MealPlanEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// Manual TypeAdapters (no build_runner needed)
class MealTypeAdapter extends TypeAdapter<MealType> {
  @override
  final int typeId = 2;

  @override
  MealType read(BinaryReader reader) {
    return MealType.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, MealType obj) {
    writer.writeByte(obj.index);
  }
}

class MealPlanEntryAdapter extends TypeAdapter<MealPlanEntry> {
  @override
  final int typeId = 3;

  @override
  MealPlanEntry read(BinaryReader reader) {
    final jsonString = reader.readString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return MealPlanEntry.fromJson(json);
  }

  @override
  void write(BinaryWriter writer, MealPlanEntry obj) {
    final jsonString = jsonEncode(obj.toJson());
    writer.writeString(jsonString);
  }
}

class DailyMealPlanAdapter extends TypeAdapter<DailyMealPlan> {
  @override
  final int typeId = 4;

  @override
  DailyMealPlan read(BinaryReader reader) {
    final jsonString = reader.readString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return DailyMealPlan.fromJson(json);
  }

  @override
  void write(BinaryWriter writer, DailyMealPlan obj) {
    final jsonString = jsonEncode(obj.toJson());
    writer.writeString(jsonString);
  }
}

