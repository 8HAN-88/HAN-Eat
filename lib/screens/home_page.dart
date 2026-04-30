// lib/screens/home_page.dart
import 'package:flutter/material.dart';
import '../models/analysis_mode.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  List<Recipe> _recipes = [];
  List<Recipe> _favorites = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final favs = await ApiService.getFavorites();
      setState(() => _favorites = favs);
    } catch (e) {
      debugPrint('Fav load error: $e');
    }
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService.searchRecipes(
        q,
        mode: AnalysisMode.all,
        language: 'ru',
      );
      if (!mounted) return;
      setState(() => _recipes = res);
    } catch (e) {
      debugPrint('Search error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка поиска: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool isFavorite(int id) => _favorites.any((r) => r.id == id);

  Future<void> toggleFavorite(Recipe r) async {
    try {
      if (isFavorite(r.id)) {
        await ApiService.removeFavorite(r.id);
        _favorites.removeWhere((e) => e.id == r.id);
      } else {
        await ApiService.addFavorite(r);
        _favorites.add(r);
      }
      setState(() {});
    } catch (e) {
      debugPrint('Toggle fav error: $e');
    }
  }

  void openRecipe(Recipe r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailPage(
          recipe: r,
          isFavorite: isFavorite(r.id),
          onToggle: () async {
            await toggleFavorite(r);
          },
        ),
      ),
    );
  }

  Widget recipeTile(Recipe r) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => openRecipe(r),
        leading: r.image == null || r.image!.isEmpty
            ? const SizedBox(
                width: 70,
                height: 70,
                child: Icon(Icons.image_not_supported),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  r.image!,
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
        title: Text(r.title),
        subtitle: Text('Использовано ингредиентов: ${r.usedIngredientCount}'),
        trailing: IconButton(
          icon: Icon(isFavorite(r.id) ? Icons.favorite : Icons.favorite_border),
          color: isFavorite(r.id) ? Colors.red : Colors.grey,
          onPressed: () => toggleFavorite(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HAN Menu'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Рецепты'),
              Tab(text: 'Избранное'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText:
                          'Введите ингредиенты (например: курица, картошка)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _search,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _recipes.isEmpty
                      ? const Center(
                          child: Text('Введите ингредиенты для поиска 🍅'),
                        )
                      : ListView.builder(
                          itemCount: _recipes.length,
                          itemBuilder: (_, i) => recipeTile(_recipes[i]),
                        ),
                ),
              ],
            ),
            _favorites.isEmpty
                ? const Center(child: Text('Нет избранных'))
                : ListView.builder(
                    itemCount: _favorites.length,
                    itemBuilder: (_, i) => recipeTile(_favorites[i]),
                  ),
          ],
        ),
      ),
    );
  }
}
