import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final recipe = await ApiService.getRecipeById(widget.recipeId);
    if (!mounted) return;
    if (recipe == null) {
      setState(() {
        _loading = false;
        _error = 'Рецепт не найден';
      });
      return;
    }
    final favorites = await ApiService.getFavorites();
    if (!mounted) return;
    final isFav = favorites.any((r) => r.id == recipe.id);
    setState(() {
      _recipe = recipe;
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.restaurant_menu,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Не удалось загрузить рецепт',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
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
