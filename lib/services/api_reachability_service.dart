import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/network/api_endpoint_resolver.dart';
import '../core/network/haneat_http_client.dart';
import '../core/platform/web_page_visibility.dart';
import 'auth_service.dart';
import 'feed_sync_service.dart';
import 'saved_posts_service.dart';
import 'server_config.dart';

/// Проверка доступности API (/health) с debounce и автопереподключением.
class ApiReachabilityService {
  ApiReachabilityService._();

  static ApiReachabilityService? _instance;
  static ApiReachabilityService get instance {
    return _instance ??= ApiReachabilityService._();
  }

  static Future<void> init() async {
    final svc = instance;
    if (svc._started) return;
    svc._started = true;

    registerWebPageVisibilityListener(svc.warmUp);

    unawaited(svc.checkNow());
    svc._schedulePeriodicCheck();

    Connectivity().onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      if (online) {
        unawaited(svc.warmUp());
      } else {
        svc._applyReachable(false);
      }
    });
  }

  final ValueNotifier<bool> isApiReachable = ValueNotifier(true);

  Timer? _timer;
  bool _started = false;
  int _consecutiveFailures = 0;
  bool _reconnectInFlight = false;
  bool _warmUpInFlight = false;
  DateTime? _lastWarmUpAt;

  static const Duration _warmUpMinInterval = Duration(seconds: 20);

  Duration get _healthyInterval =>
      kIsWeb ? const Duration(seconds: 45) : const Duration(seconds: 50);

  Duration get _unhealthyInterval =>
      kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 10);

  Duration get _probeTimeout => isApiReachable.value
      ? (kIsWeb ? const Duration(seconds: 10) : const Duration(seconds: 12))
      : (kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 10));

  int get _failuresBeforeDown => kIsWeb ? 3 : 3;

  void _schedulePeriodicCheck() {
    _timer?.cancel();
    final interval =
        isApiReachable.value ? _healthyInterval : _unhealthyInterval;
    _timer = Timer.periodic(interval, (_) {
      unawaited(checkNow());
    });
  }

  Future<bool> checkNow() async {
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/health');
      final response = await HanEatHttpClient.shared
          .get(uri)
          .timeout(_probeTimeout);
      if (response.statusCode == 200) {
        _consecutiveFailures = 0;
        _applyReachable(true);
        return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ApiReachabilityService: $e');
      await ApiEndpointResolver.revalidateIfNeeded();
      try {
        final uri = Uri.parse('${ServerConfig.baseUrl}/health');
        final response = await HanEatHttpClient.shared
            .get(uri)
            .timeout(_probeTimeout);
        if (response.statusCode == 200) {
          _consecutiveFailures = 0;
          _applyReachable(true);
          return true;
        }
      } catch (e2) {
        if (kDebugMode) debugPrint('ApiReachabilityService retry: $e2');
      }
    }

    _consecutiveFailures++;
    if (_consecutiveFailures >= _failuresBeforeDown) {
      _applyReachable(false);
    }
    return isApiReachable.value;
  }

  void _applyReachable(bool reachable) {
    final wasReachable = isApiReachable.value;
    final changed = wasReachable != reachable;
    if (changed) {
      isApiReachable.value = reachable;
      if (!reachable) {
        _consecutiveFailures = _failuresBeforeDown;
      }
      _schedulePeriodicCheck();
      if (kDebugMode) {
        debugPrint(
          'ApiReachabilityService: ${reachable ? "API OK" : "API unreachable"}',
        );
      }
      if (reachable && !wasReachable) {
        unawaited(_onReconnected());
      }
    }
  }

  Future<void> _onReconnected() async {
    if (_reconnectInFlight) return;
    _reconnectInFlight = true;
    try {
      if (AuthService.instance.currentUser != null) {
        await AuthService.getAccessTokenForApi();
        unawaited(
          SavedPostsService.processPendingOps().catchError((Object e) {
            if (kDebugMode) debugPrint('reconnect processPendingOps: $e');
          }),
        );
        try {
          await FeedSyncService.ensureInitialized();
          unawaited(FeedSyncService.instance.syncFeedInBackground());
        } catch (e) {
          if (kDebugMode) debugPrint('reconnect feed sync: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ApiReachabilityService reconnect: $e');
    } finally {
      _reconnectInFlight = false;
    }
  }

  /// Прогрев сессии после возврата из фона / на вкладку (не чаще раза в 20 с).
  Future<void> warmUp() async {
    final now = DateTime.now();
    if (_warmUpInFlight) return;
    if (_lastWarmUpAt != null &&
        now.difference(_lastWarmUpAt!) < _warmUpMinInterval) {
      return;
    }
    _warmUpInFlight = true;
    _lastWarmUpAt = now;
    try {
      final ok = await checkNow();
      if (!ok || AuthService.instance.currentUser == null) return;
      try {
        await AuthService.getAccessTokenForApi();
      } catch (e) {
        if (kDebugMode) debugPrint('warmUp token refresh: $e');
      }
    } finally {
      _warmUpInFlight = false;
    }
  }
}
