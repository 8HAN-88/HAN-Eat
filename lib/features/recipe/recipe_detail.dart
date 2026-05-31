import 'package:flutter/material.dart';
import '../../models/recipe_model.dart';
import '../../services/recipe_service.dart';
import '../../services/favorites_service.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({super.key});

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  RecipeModel? _recipe;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initFromArgs();
  }

  Future<void> _initFromArgs() async {
    if (_recipe != null || _loading) return;
    final args = ModalRoute.of(context)!.settings.arguments;
    String? id;
    if (args is RecipeModel) {
      _recipe = args;
      id = args.id;
    } else if (args is String) {
      id = args;
    } else if (args is Map && args['id'] != null) {
      id = args['id'] as String?;
    }

    if (id == null) {
      // nothing to load
      return;
    }

    setState(() => _loading = true);
    final detailed = await RecipeService.instance.fetchDetailsAndCache(id);
    setState(() {
      _recipe = detailed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_recipe == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Рецепт')),
        body: const Center(
          child: Text('Рецепт не найден'),
        ),
      );
    }

    final recipe = _recipe!;
    final isFav = FavoritesService.instance.isFavorite(recipe.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.title),
        actions: [
          IconButton(
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.red : null),
            onPressed: () =>
                FavoritesService.instance.toggleFavorite(recipe.id),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (recipe.image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(recipe.image!),
            ),
          const SizedBox(height: 12),
          Text('Cook time: ${recipe.cookTime} min',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Ingredients',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...recipe.ingredients.map((i) => ListTile(title: Text(i))),
          const SizedBox(height: 8),
          const Text('Steps',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...recipe.steps.asMap().entries.map(
                (e) => ListTile(
                  leading: CircleAvatar(child: Text('${e.key + 1}')),
                  title: Text(e.value),
                ),
              ),
        ]),
      ),
    );
  }
}
