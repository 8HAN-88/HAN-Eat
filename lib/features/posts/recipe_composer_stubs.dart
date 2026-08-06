import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporary no-op stand-ins so legacy recipe composer code still typechecks
/// after kitchen removal. Recipe mode is disabled in social UI.

typedef ChannelRecipeVisibilityMode = String;

class RecipeVisibilitySelector extends StatelessWidget {
  const RecipeVisibilitySelector({
    super.key,
    required this.value,
    required this.hasCreator,
    required this.onChanged,
    this.channelMode,
  });

  final String value;
  final bool hasCreator;
  final ValueChanged<String> onChanged;
  final ChannelRecipeVisibilityMode? channelMode;

  static String defaultForChannel(String? mode, {required bool hasCreator}) =>
      'public';

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<String?> showChangeRecipeVisibilitySheet(
  BuildContext context, {
  required String current,
  required bool hasCreator,
}) async =>
    null;

class RecipeVisibilityBadge extends StatelessWidget {
  const RecipeVisibilityBadge({
    super.key,
    required this.visibility,
    this.compact = false,
  });

  final String visibility;
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class RecipeOriginCountryField extends StatelessWidget {
  const RecipeOriginCountryField({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selectedCode;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

int? parseIntField(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

double? parseDoubleField(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

class RecipeNutritionFormSection extends ConsumerWidget {
  const RecipeNutritionFormSection({
    super.key,
    required this.caloriesController,
    required this.proteinController,
    required this.carbsController,
    required this.fatController,
    required this.fiberController,
    required this.getTitle,
    required this.getIngredients,
    required this.getStepTexts,
    this.getServings,
    this.getDescription,
  });

  final TextEditingController caloriesController;
  final TextEditingController proteinController;
  final TextEditingController carbsController;
  final TextEditingController fatController;
  final TextEditingController fiberController;
  final String Function() getTitle;
  final List<String> Function() getIngredients;
  final List<String> Function() getStepTexts;
  final int? Function()? getServings;
  final String? Function()? getDescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

Future<void> showCreatorRecipeUpsellSheet(BuildContext context) async {}
