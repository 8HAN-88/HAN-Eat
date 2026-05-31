import 'package:flutter/material.dart';

import '../../models/recipe_model.dart';
import '../../screens/detail_page.dart';
import '../../services/favorites_service.dart';
import '../../services/recipe_service.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  void _openDetail(BuildContext context, RecipeModel r) {
    final recipe = r.toRecipe();
    final favIds = FavoritesService.instance.favorites.value;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(
          recipe: recipe,
          isFavorite: favIds.contains(r.id),
          onToggle: () => FavoritesService.instance.toggleFavorite(r.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
      ),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.instance.favorites,
        builder: (context, favs, _) {
          return ValueListenableBuilder<List<RecipeModel>>(
            valueListenable: RecipeService.instance.recipes,
            builder: (context, allRecipes, __) {
              final favList = allRecipes
                  .where((r) => favs.contains(r.id))
                  .toList();
              if (favList.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      favs.isEmpty
                          ? 'Пока нет избранного.\nДобавляйте рецепты из меню или ленты.'
                          : 'Избранные рецепты не найдены в каталоге.\n'
                              'Откройте меню и обновите список рецептов.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: favList.length,
                itemBuilder: (context, index) {
                  final r = favList[index];
                  return ListTile(
                    leading: r.image != null && r.image!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              r.image!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.restaurant),
                            ),
                          )
                        : const Icon(Icons.restaurant),
                    title: Text(r.title),
                    subtitle: Text(
                      '${r.cookTime} мин · ${r.ingredients.length} ингр.',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () =>
                          FavoritesService.instance.toggleFavorite(r.id),
                    ),
                    onTap: () => _openDetail(context, r),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
