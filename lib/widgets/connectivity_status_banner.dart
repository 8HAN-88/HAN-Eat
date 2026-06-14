import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../services/api_reachability_service.dart';
import '../services/feed_sync_service.dart';

/// Глобальный баннер: нет сети / сервер недоступен / восстановление.
class ConnectivityStatusBanner extends StatefulWidget {
  const ConnectivityStatusBanner({super.key});

  @override
  State<ConnectivityStatusBanner> createState() =>
      _ConnectivityStatusBannerState();
}

class _ConnectivityStatusBannerState extends State<ConnectivityStatusBanner> {
  bool? _lastDeviceOnline;
  bool? _lastApiReachable;
  Timer? _recoveredTimer;
  bool _showRecovered = false;

  late final VoidCallback _onConnectivityChanged;

  @override
  void initState() {
    super.initState();
    _onConnectivityChanged = _handleConnectivityChanged;
    FeedSyncService.onlineListenable.addListener(_onConnectivityChanged);
    ApiReachabilityService.instance.isApiReachable
        .addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _recoveredTimer?.cancel();
    FeedSyncService.onlineListenable.removeListener(_onConnectivityChanged);
    ApiReachabilityService.instance.isApiReachable
        .removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _handleConnectivityChanged() {
    if (!mounted) return;
    final deviceOnline = FeedSyncService.onlineListenable.value;
    final apiReachable = ApiReachabilityService.instance.isApiReachable.value;

    final wasOffline = _lastDeviceOnline == false ||
        (_lastDeviceOnline == true && _lastApiReachable == false);
    final isHealthy = deviceOnline && apiReachable;

    if (_lastDeviceOnline != null) {
      if (!isHealthy &&
          (_lastDeviceOnline != deviceOnline ||
              _lastApiReachable != apiReachable)) {
        if (!deviceOnline || (deviceOnline && !apiReachable)) {
          AppHaptics.medium();
        }
      } else if (wasOffline && isHealthy) {
        AppHaptics.light();
        _recoveredTimer?.cancel();
        setState(() => _showRecovered = true);
        _recoveredTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showRecovered = false);
        });
        _lastDeviceOnline = deviceOnline;
        _lastApiReachable = apiReachable;
        return;
      }
    }

    if (_lastDeviceOnline != deviceOnline ||
        _lastApiReachable != apiReachable ||
        _showRecovered) {
      setState(() {
        _lastDeviceOnline = deviceOnline;
        _lastApiReachable = apiReachable;
      });
    } else {
      _lastDeviceOnline = deviceOnline;
      _lastApiReachable = apiReachable;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceOnline = FeedSyncService.onlineListenable.value;
    final apiReachable = ApiReachabilityService.instance.isApiReachable.value;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_showRecovered && deviceOnline && apiReachable) {
      if (kIsWeb) return const SizedBox.shrink();
      return _BannerShell(
        color: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        icon: Icons.cloud_done_outlined,
        message: 'Снова в сети',
        textTheme: textTheme,
      );
    }

    if (deviceOnline && apiReachable) {
      return const SizedBox.shrink();
    }

    if (!deviceOnline) {
      return _BannerShell(
        color: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.wifi_off_rounded,
        message:
            'Нет интернета. Лента, избранное и недавние чаты доступны офлайн.',
        textTheme: textTheme,
      );
    }

    return _BannerShell(
      color: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      icon: Icons.cloud_off_outlined,
      message:
          'Сервер временно недоступен. Показываем сохранённые данные, подключимся автоматически.',
      textTheme: textTheme,
      action: TextButton(
        onPressed: () =>
            unawaited(ApiReachabilityService.instance.checkNow()),
        child: Text(
          'Повторить',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}

class _BannerShell extends StatelessWidget {
  const _BannerShell({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.message,
    required this.textTheme,
    this.action,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String message;
  final TextTheme textTheme;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Material(
        color: color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: foreground,
                      height: 1.2,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
