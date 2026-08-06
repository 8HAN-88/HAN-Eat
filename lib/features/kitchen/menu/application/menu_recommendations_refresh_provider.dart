import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Инкремент при каждом открытии вкладки «Меню» — сброс устаревшего кэша рекомендаций.
final menuRecommendationsRefreshProvider = StateProvider<int>((ref) => 0);
