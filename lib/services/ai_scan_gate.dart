import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../features/subscription/presentation/widgets/subscription_visuals.dart';
import '../features/subscription/subscription_copy.dart';
import 'api_service.dart';
import 'product_analytics.dart';

/// Проверка AI scan перед камерой: soft warning / paywall без счётчиков.
class AiScanGate {
  static AiScanStatus? _cachedStatus;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 30);

  /// Сбросить кэш после успешного скана (лимиты могли измениться).
  static void invalidateCache() {
    _cachedStatus = null;
    _cachedAt = null;
  }

  static bool get _cacheValid {
    if (_cachedStatus == null || _cachedAt == null) return false;
    return DateTime.now().difference(_cachedAt!) < _cacheTtl;
  }

  /// Начисление на backend + проверка доступа. `false` = не открывать камеру.
  static Future<bool> ensureCanOpenScanner(BuildContext context) async {
    if (_cacheValid && _cachedStatus!.canScan) {
      if (_cachedStatus!.softWarning) {
        _showSoftWarningSnackBar(context);
      }
      unawaited(_refreshStatus(context));
      return true;
    }

    return _refreshStatus(context);
  }

  static Future<bool> _refreshStatus(BuildContext context) async {
    final status = await ApiService.touchAiScanCreditsSilently();
    if (status == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось проверить лимиты AI-скана. Проверьте подключение и попробуйте снова.',
            ),
          ),
        );
      }
      return false;
    }

    _cachedStatus = status;
    _cachedAt = DateTime.now();

    if (!status.canScan) {
      await _showSoftPaywall(context, isPlus: status.isPlus);
      return false;
    }
    if (status.softWarning) {
      _showSoftWarningSnackBar(context);
      unawaited(
        ProductAnalytics.logEvent(eventType: 'ai_scan_soft_warning_shown'),
      );
    }
    return true;
  }

  static void _showSoftWarningSnackBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        content: Text(
          SubscriptionCopy.aiScanSoftWarning,
          style: TextStyle(color: scheme.onSurface),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static Future<void> _showSoftPaywall(
    BuildContext context, {
    required bool isPlus,
  }) async {
    unawaited(
      ProductAnalytics.logEvent(
        eventType: 'ai_scan_paywall_view',
        metadata: {'is_plus': isPlus, 'source': 'pre_scan'},
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
          child: AiScanExhaustedPaywall(
            isPlus: isPlus,
            onChoosePlan: () {
              ProductAnalytics.logEvent(
                eventType: 'ai_scan_paywall_cta',
                metadata: {'source': 'pre_scan'},
              );
              Navigator.of(ctx).pop();
              if (!isPlus) {
                context.push(SubscriptionRoute.pathWithProduct('ai'));
              }
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
        );
      },
    );
  }
}
