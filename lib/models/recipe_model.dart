import 'package:hive/hive.dart';

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

  RecipeModel({
    required this.id,
    required this.title,
    required this.cookTime,
    required this.ingredients,
    required this.steps,
    this.image,
    required this.updatedAt,
  });

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
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cookTime': cookTime,
        'ingredients': ingredients,
        'steps': steps,
        'image': image,
        'updatedAt': updatedAt.toIso8601String(),
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
    final ingredients = (reader.readList() ?? []).cast<String>();
    final steps = (reader.readList() ?? []).cast<String>();
    final hasImage = reader.readBool();
    final image = hasImage ? reader.readString() : null;
    final updatedAtMillis = reader.readInt();
    return RecipeModel(
      id: id,
      title: title,
      cookTime: cookTime,
      ingredients: ingredients,
      steps: steps,
      image: image,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
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
  }
}
