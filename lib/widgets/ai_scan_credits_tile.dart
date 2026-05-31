import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';

/// Настройки AI scan — без счётчиков (premium UX).
class AiScanCreditsTile extends StatefulWidget {
  const AiScanCreditsTile({super.key});

  @override
  State<AiScanCreditsTile> createState() => _AiScanCreditsTileState();
}

class _AiScanCreditsTileState extends State<AiScanCreditsTile> {
  bool _hasAi = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (AuthService.instance.currentUser == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      unawaited(ApiService.touchAiScanCreditsSilently());
      final status = await SubscriptionService.getSubscriptionStatus();
      if (!mounted) return;
      setState(() {
        _hasAi = status.hasAi;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.instance.currentUser == null) {
      return const SizedBox.shrink();
    }

    final subtitle = _loading
        ? 'Загрузка…'
        : _hasAi
            ? 'Расширенный AI: сканирование блюд, питание и планы меню'
            : 'Сканируйте блюда и узнавайте калории с H.A.N. AI';

    return ListTile(
      leading: const Icon(Icons.document_scanner_outlined),
      title: const Text('AI-сканирование блюд'),
      subtitle: Text(subtitle),
      trailing: _loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _hasAi
              ? const Icon(Icons.check_circle_outline)
              : TextButton(
                  onPressed: () => context.push(SubscriptionRoute.path),
                  child: const Text('Подробнее'),
                ),
      onTap: () => context.push(
        _hasAi ? SubscriptionRoute.path : SubscriptionRoute.pathWithProduct('ai'),
      ),
    );
  }
}
