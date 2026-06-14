import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_build_config.dart';
import 'haneat_http_client.dart';

/// Выбор API-хоста: домен или IP, если DNS домена недоступен.
class ApiEndpointResolver {
  ApiEndpointResolver._();

  static const productionHost = 'api.haneat.app';
  static const productionFallbackIp = '89.19.216.60';

  /// Ожидаемые A-записи production (Timeweb). Иные IP → fallback на IP.
  static const productionExpectedIps = {productionFallbackIp};

  static String? _resolvedRoot;
  static bool usingIpFallback = false;

  static Future<void> resolve() async {
    if (_resolvedRoot != null) return;

    final configured = AppBuildConfig.apiBaseRoot;
    final uri = Uri.tryParse(configured);
    final host = (uri?.host ?? '').toLowerCase();

    if (host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '10.0.2.2' ||
        host.isEmpty) {
      _resolvedRoot = configured;
      return;
    }

    if (_isIpv4(host)) {
      _resolvedRoot = configured;
      usingIpFallback = host == productionFallbackIp;
      return;
    }

    if (kIsWeb || host != productionHost) {
      _resolvedRoot = configured;
      return;
    }

    try {
      final addresses = await InternetAddress.lookup(productionHost)
          .timeout(const Duration(seconds: 4));
      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .map((a) => a.address)
          .toSet();
      final dnsOk = ipv4.any(productionExpectedIps.contains);
      if (addresses.isNotEmpty && dnsOk) {
        _resolvedRoot = configured;
        usingIpFallback = false;
        debugPrint('📡 API: DNS OK ($productionHost → ${ipv4.join(", ")})');
        return;
      }
      if (addresses.isNotEmpty && !dnsOk) {
        debugPrint(
          '📡 API: DNS $productionHost → ${ipv4.join(", ")} (не Timeweb), '
          'fallback $productionFallbackIp',
        );
      }
    } catch (e) {
      debugPrint('📡 API: DNS fail ($e)');
    }

    _resolvedRoot = 'https://$productionFallbackIp';
    usingIpFallback = true;
    debugPrint(
      '📡 API: используем $productionFallbackIp (DNS $productionHost недоступен или неверен)',
    );
  }

  static String get resolvedRoot =>
      _resolvedRoot ?? AppBuildConfig.apiBaseRoot;

  /// Повторный выбор хоста после сбоя сети (домен ↔ IP).
  static Future<void> revalidateIfNeeded() async {
    final configured = AppBuildConfig.apiBaseRoot;
    final uri = Uri.tryParse(configured);
    final host = (uri?.host ?? '').toLowerCase();
    if (host != productionHost) return;

    final previous = _resolvedRoot;
    _resolvedRoot = null;
    usingIpFallback = false;
    await resolve();
    if (previous != _resolvedRoot) {
      // ignore: invalid_use_of_visible_for_testing_member
      HanEatHttpClient.resetForTest();
      debugPrint('📡 API: endpoint switched → $resolvedRoot');
    }
  }

  static bool hostNeedsSslRelaxation(String host) =>
      usingIpFallback && host == productionFallbackIp;

  /// Подмена api.haneat.app → IP в URL с бэкенда, пока DNS не починен.
  static String rewriteProductionHost(String url) {
    if (!usingIpFallback || url.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      if (uri.host.toLowerCase() == productionHost) {
        return uri.replace(host: productionFallbackIp).toString();
      }
    } catch (_) {}
    return url;
  }

  static bool _isIpv4(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);

  @visibleForTesting
  static void resetForTest() {
    _resolvedRoot = null;
    usingIpFallback = false;
  }
}
