enum AnalysisMode {
  recipe,
  calories,
  all,
}

extension AnalysisModeX on AnalysisMode {
  String get apiValue => name;

  String get displayName {
    switch (this) {
      case AnalysisMode.recipe:
        return 'Рецепт';
      case AnalysisMode.calories:
        return 'Калории';
      case AnalysisMode.all:
        return 'Все вместе';
    }
  }
}

AnalysisMode analysisModeFromString(String? raw) {
  switch (raw) {
    case 'recipe':
      return AnalysisMode.recipe;
    case 'calories':
      return AnalysisMode.calories;
    case 'all':
    default:
      return AnalysisMode.all;
  }
}

