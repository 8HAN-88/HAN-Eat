import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/recipe_model.dart';
import '../data/mock_recipes.dart';
import 'recipe_api_service.dart';

class RecipeService {
  static late final RecipeService instance;
  static const String _boxName = 'recipes_box';

  late final Box _box;
  final ValueNotifier<List<RecipeModel>> recipes = ValueNotifier([]);
  final ValueNotifier<bool> online = ValueNotifier(false);

  StreamSubscription<dynamic>? _connectivitySub;

  RecipeService._internal(this._box) {
    _loadFromBox();
    _startConnectivityMonitor();
  }

  static Future<void> init() async {
    // ensure adapter registered by bootstrap before calling
    final box = await Hive.openBox(_boxName);
    instance = RecipeService._internal(box);
  }

  void _loadFromBox() {
    final list = <RecipeModel>[];
    for (final key in _box.keys) {
      final raw = _box.get(key) as RecipeModel;
      list.add(raw);
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    recipes.value = list;
  }

  Future<void> _startConnectivityMonitor() async {
    final conn = Connectivity();
    final initial = await conn.checkConnectivity();
    online.value = !initial.contains(ConnectivityResult.none);

    _connectivitySub = conn.onConnectivityChanged.listen((result) {
      final isOnline = !result.contains(ConnectivityResult.none);
      final prev = online.value;
      online.value = isOnline;
      if (!prev && isOnline) {
        // regained connectivity -> attempt sync
        manualSync();
      }
    });
  }

  // Manual sync: fetch remote (real API if online) and merge with local
  Future<void> manualSync() async {
    try {
      final remote = await _fetchRemoteRecipes();
      await _mergeRemote(remote);
    } catch (e) {
      if (kDebugMode) debugPrint('manualSync failed: $e');
    }
  }

  // New: search remote by query and cache results
  Future<void> searchRemoteAndCache(String query) async {
    try {
      final remote = await RecipeApiService.searchRecipes(query, number: 25);
      if (remote.isNotEmpty) {
        await cacheRecipes(remote);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('searchRemoteAndCache failed: $e');
    }
  }

  // Simulated remote: use API when online, otherwise fallback mock
  Future<List<RecipeModel>> _fetchRemoteRecipes() async {
    if (online.value) {
      // Basic remote fetch: get some popular or empty query -> we use mock as fallback
      try {
        final remote = await RecipeApiService.searchRecipes('', number: 20);
        if (remote.isNotEmpty) return remote;
      } catch (e) {
        if (kDebugMode) debugPrint('remote fetch error: $e');
      }
    }
    if (kReleaseMode) {
      return [];
    }
    return getMockRecipeModels();
  }

  Future<void> _mergeRemote(List<RecipeModel> remote) async {
    // Build maps
    final Map<String, RecipeModel> localMap = {
      for (final r in recipes.value) r.id: r,
    };
    final Map<String, RecipeModel> remoteMap = {
      for (final r in remote) r.id: r
    };

    // Merge: choose newer updatedAt
    final mergedKeys = {...localMap.keys, ...remoteMap.keys};
    for (final id in mergedKeys) {
      final local = localMap[id];
      final rem = remoteMap[id];
      RecipeModel chosen;
      if (local == null) {
        chosen = rem!;
      } else if (rem == null) {
        chosen = local;
      } else {
        chosen = rem.updatedAt.isAfter(local.updatedAt) ? rem : local;
      }
      await _box.put(id, chosen);
    }

    // Reload notifier
    _loadFromBox();
  }

  List<RecipeModel> getAll() => recipes.value;

  RecipeModel? getById(String id) {
    try {
      return recipes.value.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  // Fetch detailed recipe by id; if cache is fresh (24h) return cached, otherwise try remote and cache.
  Future<RecipeModel?> fetchDetailsAndCache(String id,
      {Duration maxAge = const Duration(hours: 24)}) async {
    final cached = getById(id);
    if (cached != null &&
        DateTime.now().difference(cached.updatedAt) < maxAge) {
      return cached;
    }

    if (online.value) {
      try {
        final detailed = await RecipeApiService.getRecipeDetails(id);
        if (detailed != null) {
          await _box.put(detailed.id, detailed);
          _loadFromBox();
          return detailed;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('fetchDetailsAndCache error: $e');
      }
    }

    // Fallback to cached (even if stale) or null
    return cached;
  }

  Future<void> cacheRecipes(List<RecipeModel> items) async {
    for (final r in items) {
      await _box.put(r.id, r);
    }
    _loadFromBox();
  }

  void dispose() {
    _connectivitySub?.cancel();
    recipes.dispose();
    online.dispose();
  }
}
