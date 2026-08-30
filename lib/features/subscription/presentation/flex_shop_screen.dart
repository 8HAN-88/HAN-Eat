import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import 'flex_preview_sheet.dart';

class FlexShopScreen extends StatefulWidget {
  const FlexShopScreen({super.key});

  @override
  State<FlexShopScreen> createState() => _FlexShopScreenState();
}

class _FlexShopScreenState extends State<FlexShopScreen>
    with WidgetsBindingObserver {
  FlexShop? _shop;
  bool _loading = true;
  String? _error;
  bool _awaitingCheckoutReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingCheckoutReturn) {
      _awaitingCheckoutReturn = false;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shop = await FlexSubscriptionApi.shop();
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
  }

  Future<void> _buyLevel(int level) async {
    try {
      final preview = await FlexSubscriptionApi.preview(level);
      if (!mounted) return;
      final ok = await showFlexPreviewSheet(context, preview: preview);
      if (ok != true || !mounted) return;
      await FlexSubscriptionApi.checkout(level);
      _awaitingCheckoutReturn = true;
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  String _status(FlexFeature feature) {
    switch (feature.shopState) {
      case 'available':
        return '🟢 Доступна';
      case 'plus_ten':
        return '🔵 Доступна за +10 ₽';
      default:
        return '🔒 Требуется уровень ${feature.assignedLevel}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Все возможности'),
        actions: [
          IconButton(
            onPressed: () => context.push(FlexSubscriptionRoute.path),
            icon: const Icon(Icons.workspace_premium_outlined),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _shop!.features.length,
                    itemBuilder: (context, index) {
                      final feature = _shop!.features[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                feature.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              if ((feature.description ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(feature.description!),
                              ],
                              const SizedBox(height: 8),
                              Text(_status(feature)),
                              if (feature.shopState != 'available') ...[
                                const SizedBox(height: 10),
                                FilledButton.tonal(
                                  onPressed: () => _buyLevel(feature.assignedLevel),
                                  child: Text(
                                    feature.shopState == 'plus_ten'
                                        ? 'Открыть за +10 ₽'
                                        : 'Перейти на уровень ${feature.assignedLevel}',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
