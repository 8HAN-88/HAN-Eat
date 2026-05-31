import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../widgets/app_empty_state.dart';
import 'detail_page.dart';

/// Экран загрузки рецепта по ID (для открытия по ссылке haneat://recipe/id).
class RecipeByIdScreen extends StatefulWidget {
  const RecipeByIdScreen({super.key, required this.recipeId});

  final int recipeId;

  @override
  State<RecipeByIdScreen> createState() => _RecipeByIdScreenState();
}

class _RecipeByIdScreenState extends State<RecipeByIdScreen> {
  Recipe? _recipe;
  bool _isFavorite = false;
  bool _loading = true;
  String? _error;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notFound = false;
    });
    final result = await ApiService.loadRecipeById(widget.recipeId);
    if (!mounted) return;
    if (result.recipe == null) {
      setState(() {
        _loading = false;
        _notFound = result.notFound;
        _error = result.notFound
            ? 'Рецепт не найден'
            : (result.errorMessage ?? 'Не удалось загрузить рецепт');
      });
      return;
    }
    final favorites = await ApiService.getFavorites();
    if (!mounted) return;
    final isFav = favorites.any((r) => r.id == result.recipe!.id);
    setState(() {
      _recipe = result.recipe;
      _isFavorite = isFav;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_recipe == null) return;
    if (_isFavorite) {
      await ApiService.removeFavorite(_recipe!.id);
    } else {
      await ApiService.addFavorite(_recipe!);
    }
    if (mounted) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Рецепт')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _recipe == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Рецепт')),
        body: AppEmptyState(
          icon: _notFound
              ? Icons.restaurant_menu_outlined
              : Icons.cloud_off_rounded,
          title: _notFound ? 'Рецепт не найден' : 'Не удалось загрузить',
          subtitle: _error,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_notFound)
                FilledButton(
                  onPressed: _load,
                  child: const Text('Повторить'),
                ),
              if (!_notFound) const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    }
    return DetailPage(
      recipe: _recipe!,
      isFavorite: _isFavorite,
      onToggle: _toggleFavorite,
    );
  }
}
