import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_bootstrap_state.dart';
import '../core/storage/hive_bootstrap.dart';
import '../services/category_service.dart';
import '../services/favorites_service.dart';
import '../services/meal_plan_service.dart';
import '../services/recipe_service.dart';
import '../services/shopping_service.dart';

/// Какие локальные сервисы должны быть готовы перед показом [child].
enum DeferredLocalService {
  shopping,
  recipe,
  favorites,
  mealPlan,
  categories,
}

/// Ждёт [AppBootstrapState.servicesReady] или догружает Hive-сервисы по запросу.
class ServicesReadyGate extends StatefulWidget {
  const ServicesReadyGate({
    super.key,
    required this.child,
    this.services = const [
      DeferredLocalService.shopping,
      DeferredLocalService.recipe,
      DeferredLocalService.favorites,
    ],
    this.placeholder,
  });

  final Widget child;
  final List<DeferredLocalService> services;
  final Widget? placeholder;

  @override
  State<ServicesReadyGate> createState() => _ServicesReadyGateState();
}

class _ServicesReadyGateState extends State<ServicesReadyGate> {
  bool _ready = AppBootstrapState.servicesReady.value;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    AppBootstrapState.servicesReady.addListener(_onServicesReady);
    if (!_ready) {
      unawaited(_ensureServices());
    }
  }

  void _onServicesReady() {
    if (AppBootstrapState.servicesReady.value && mounted) {
      setState(() {
        _ready = true;
        _error = null;
      });
    }
  }

  Future<void> _ensureServices() async {
    if (_loading || _ready) return;
    _loading = true;
    if (mounted) setState(() => _error = null);
    try {
      await ensureHiveReady();
      final futures = <Future<void>>[];
      for (final s in widget.services) {
        switch (s) {
          case DeferredLocalService.shopping:
            futures.add(ShoppingService.ensureInitialized());
          case DeferredLocalService.recipe:
            futures.add(RecipeService.ensureInitialized());
          case DeferredLocalService.favorites:
            futures.add(FavoritesService.ensureInitialized());
          case DeferredLocalService.mealPlan:
            futures.add(MealPlanService.ensureInitialized());
          case DeferredLocalService.categories:
            futures.add(CategoryService.ensureInitialized());
        }
      }
      await Future.wait(futures);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('ServicesReadyGate: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    AppBootstrapState.servicesReady.removeListener(_onServicesReady);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text('Не удалось загрузить данные', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _ensureServices,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    return widget.placeholder ??
        const Center(child: CircularProgressIndicator());
  }
}
