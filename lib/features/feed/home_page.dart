import 'package:flutter/material.dart';
import '../../data/mock_recipes.dart';
import '../../services/user_service.dart';
import '../../services/favorites_service.dart';
import '../../services/auth_service.dart';
import '../../services/recipe_service.dart';
import '../../models/recipe_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  bool _searchingRemote = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HAN Eat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () => Navigator.pushNamed(context, '/shopping'),
          ),
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: () => Navigator.pushNamed(context, '/favorites'),
          ),
          IconButton(
            // community button
            icon: const Icon(Icons.group),
            tooltip: 'Community',
            onPressed: () => Navigator.pushNamed(context, '/community'),
          ),
          IconButton(
            // user search
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search users',
            onPressed: () => Navigator.pushNamed(context, '/users'),
          ),
          ValueListenableBuilder(
            valueListenable: UserService.instance.profile,
            builder: (context, value, _) {
              final profile = value as UserProfile?;
              final isSigned = AuthService.instance.currentUser != null;
              if (!isSigned || profile == null) {
                return IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => Navigator.pushNamed(context, '/profile'),
                );
              }
              return GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/profile'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: CircleAvatar(
                    radius: 16,
                    backgroundImage: profile.avatarUrl != null
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? Text(profile.displayName.isNotEmpty
                            ? profile.displayName.substring(0, 1).toUpperCase()
                            : '?')
                        : null,
                  ),
                ),
              );
            },
          ),
          // online/offline indicator
          ValueListenableBuilder<bool>(
            valueListenable: RecipeService.instance.online,
            builder: (context, online, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(online ? Icons.wifi : Icons.wifi_off,
                    color: online ? Colors.greenAccent : Colors.redAccent),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search recipes or ingredients',
              ),
              onChanged: (v) => setState(() => query = v),
              onSubmitted: (v) async {
                final q = v.trim();
                if (q.isEmpty) return;
                if (!RecipeService.instance.online.value) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Offline — search will use cache')));
                  return;
                }
                setState(() => _searchingRemote = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Searching remote recipes...')));
                try {
                  await RecipeService.instance.searchRemoteAndCache(q);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Remote search failed: $e')));
                } finally {
                  setState(() => _searchingRemote = false);
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<List<RecipeModel>>(
                valueListenable: RecipeService.instance.recipes,
                builder: (context, list, _) {
                  final results = list
                      .where((r) =>
                          r.title.toLowerCase().contains(query.toLowerCase()) ||
                          r.ingredients.any((ing) =>
                              ing.toLowerCase().contains(query.toLowerCase())))
                      .toList();
                  if (results.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () => RecipeService.instance.manualSync(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('No recipes found'))
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => RecipeService.instance.manualSync(),
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (c, i) {
                        final r = results[i];
                        final isFav =
                            FavoritesService.instance.isFavorite(r.id);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: SizedBox(
                              width: 72,
                              height: 56,
                              child: r.image != null
                                  ? Image.network(r.image!, fit: BoxFit.cover)
                                  : const Placeholder(),
                            ),
                            title: Text(r.title),
                            subtitle: Text(
                                '${r.cookTime} min • ${r.ingredients.length} ingredients'),
                            trailing: IconButton(
                              icon: Icon(
                                  isFav
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFav ? Colors.red : null),
                              onPressed: () => FavoritesService.instance
                                  .toggleFavorite(r.id),
                            ),
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/detail',
                              arguments: r,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
