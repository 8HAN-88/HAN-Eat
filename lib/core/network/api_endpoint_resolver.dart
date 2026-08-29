import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_build_config.dart';

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
      if (kIsWeb) {
        await _resolveWebSameOriginOrFallback();
      } else {
        _resolvedRoot = configured;
      }
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
    if (kIsWeb) {
      final previous = _resolvedRoot;
      _resolvedRoot = null;
      usingIpFallback = false;
      await resolve();
      if (previous != _resolvedRoot) {
        debugPrint('📡 API: endpoint switched → $resolvedRoot');
      }
      return;
    }
    if (host != productionHost) return;

    final previous = _resolvedRoot;
    _resolvedRoot = null;
    usingIpFallback = false;
    await resolve();
    if (previous != _resolvedRoot) {
      debugPrint('📡 API: endpoint switched → $resolvedRoot');
    }
  }

  static bool _isHealthJson(String body) =>
      body.contains('"status"') && !body.trimLeft().startsWith('<!');

  static bool isHealthJson(String body) => _isHealthJson(body);

  /// На web: same-origin API, если nginx проксирует /health; иначе api.haneat.app.
  static Future<void> _resolveWebSameOriginOrFallback() async {
    final page = Uri.base;
    if (page.scheme == 'file' || page.host.isEmpty) {
      _resolvedRoot = AppBuildConfig.apiBaseRoot;
      return;
    }

    final sameOrigin = '${page.scheme}://${page.host}';
    final configured = AppBuildConfig.apiBaseRoot;
    final configuredHost = Uri.tryParse(configured)?.host.toLowerCase() ?? '';
    final onProductionWeb = page.host == 'haneat.app' ||
        page.host == 'www.haneat.app' ||
        page.host == 'kitchen.haneat.app' ||
        configuredHost == 'haneat.app' ||
        configuredHost == 'www.haneat.app';

    if (!onProductionWeb) {
      _resolvedRoot = configured;
      return;
    }

    // Always pin production web to same-origin. Never fall back to
    // api.haneat.app here: CORS preflight stalls on Safari look like a white
    // screen / "server stopped responding", even when /api is healthy via nginx.
    _resolvedRoot = sameOrigin;
    usingIpFallback = false;
    // Don't await /health here — it blocked StartupShell up to 5s on 3G.
    unawaited(() async {
      final ok = await _probeHealthJson(sameOrigin);
      debugPrint(
        ok
            ? '📡 Web API: same-origin $sameOrigin'
            : '📡 Web API: same-origin $sameOrigin (health probe slow/failed, still pinned)',
      );
    }());
  }

  static Future<bool> _probeHealthJson(String root) async {
    try {
      final uri = Uri.parse('$root/health');
      final client = http.Client();
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 5))
          .whenComplete(client.close);
      return response.statusCode == 200 && _isHealthJson(response.body);
    } catch (_) {
      return false;
    }
  }

  static bool hostNeedsSslRelaxation(String host) =>
      usingIpFallback && host == productionFallbackIp;

  /// На web haneat.app — always rewrite api.haneat.app → same-origin.
  static String rewriteProductionHost(String url) {
    if (url.isEmpty) return url;
    if (kIsWeb) {
      try {
        final page = Uri.base;
        if (page.host == 'haneat.app' ||
            page.host == 'www.haneat.app' ||
            page.host == 'kitchen.haneat.app') {
          final uri = Uri.parse(url);
          if (uri.host.toLowerCase() == productionHost) {
            return uri.replace(host: page.host, scheme: page.scheme).toString();
          }
        }
      } catch (_) {}
    }
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
