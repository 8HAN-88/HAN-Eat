import 'package:flutter/material.dart';
import '../../services/favorites_service.dart';
import '../../data/mock_recipes.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.instance.favorites,
        builder: (context, favs, _) {
          final favList =
              mockRecipes.where((r) => favs.contains(r.id)).toList();
          if (favList.isEmpty) {
            return const Center(child: Text('No favorites yet'));
          }
          return ListView.builder(
            itemCount: favList.length,
            itemBuilder: (c, i) {
              final r = favList[i];
              return ListTile(
                leading: r.image != null
                    ? Image.network(r.image!, width: 72, fit: BoxFit.cover)
                    : null,
                title: Text(r.title),
                subtitle: Text('${r.cookTime} min'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () =>
                      FavoritesService.instance.toggleFavorite(r.id),
                ),
                onTap: () =>
                    Navigator.pushNamed(context, '/detail', arguments: r),
              );
            },
          );
        },
      ),
    );
  }
}
