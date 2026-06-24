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

    registerWebPageVisibilityListener(() => svc.warmUp(force: true));

    unawaited(svc.checkNow());
    svc._schedulePeriodicCheck();

    Connectivity().onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      if (online) {
        unawaited(svc.warmUp());
      } else {
        svc.isApiConnecting.value = false;
        svc._applyReachable(false);
      }
    });
  }

  final ValueNotifier<bool> isApiReachable = ValueNotifier(true);

  /// true — устройство в сети, но API ещё не ответил (как «Подключение…» в Telegram).
  final ValueNotifier<bool> isApiConnecting = ValueNotifier(false);

  final List<VoidCallback> _reconnectedListeners = [];

  static void addReconnectedListener(VoidCallback listener) {
    instance._reconnectedListeners.add(listener);
  }

  static void removeReconnectedListener(VoidCallback listener) {
    instance._reconnectedListeners.remove(listener);
  }

  void _notifyReconnected() {
    for (final listener in List<VoidCallback>.from(_reconnectedListeners)) {
      try {
        listener();
      } catch (e) {
        if (kDebugMode) debugPrint('reconnected listener: $e');
      }
    }
  }

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
      kIsWeb ? const Duration(seconds: 15) : const Duration(seconds: 10);

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
    if (FeedSyncService.onlineListenable.value) {
      isApiConnecting.value = !isApiReachable.value;
    }
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/health');
      final response = await HanEatHttpClient.withShared(
        (client) => client.get(uri).timeout(_probeTimeout),
      );
      if (response.statusCode == 200 &&
          ApiEndpointResolver.isHealthJson(response.body)) {
        _consecutiveFailures = 0;
        _applyReachable(true);
        isApiConnecting.value = false;
        return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ApiReachabilityService: $e');
      HanEatHttpClient.recreateShared();
      if (FeedSyncService.onlineListenable.value) {
        isApiConnecting.value = true;
      }
      await ApiEndpointResolver.revalidateIfNeeded();
      try {
        final uri = Uri.parse('${ServerConfig.baseUrl}/health');
        final response = await HanEatHttpClient.withShared(
          (client) => client.get(uri).timeout(_probeTimeout),
        );
        if (response.statusCode == 200 &&
          ApiEndpointResolver.isHealthJson(response.body)) {
          _consecutiveFailures = 0;
          _applyReachable(true);
          isApiConnecting.value = false;
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
    if (FeedSyncService.onlineListenable.value && !isApiReachable.value) {
      isApiConnecting.value = true;
    }
    return isApiReachable.value;
  }

  void _applyReachable(bool reachable) {
    final wasReachable = isApiReachable.value;
    final changed = wasReachable != reachable;
    if (changed) {
      isApiReachable.value = reachable;
      isApiConnecting.value =
          !reachable && FeedSyncService.onlineListenable.value;
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
        isApiConnecting.value = false;
        unawaited(_onReconnected());
      }
    } else if (reachable) {
      isApiConnecting.value = false;
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
        _notifyReconnected();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ApiReachabilityService reconnect: $e');
    } finally {
      _reconnectInFlight = false;
    }
  }

  /// Прогрев сессии после возврата из фона / на вкладку.
  Future<void> warmUp({bool force = false}) async {
    final now = DateTime.now();
    if (_warmUpInFlight) return;
    if (!force &&
        _lastWarmUpAt != null &&
        now.difference(_lastWarmUpAt!) < _warmUpMinInterval) {
      return;
    }
    _warmUpInFlight = true;
    _lastWarmUpAt = now;
    HanEatHttpClient.ensureHealthy();
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
