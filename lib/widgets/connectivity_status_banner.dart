import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../services/api_reachability_service.dart';
import '../services/feed_sync_service.dart';

/// Тонкая полоска статуса сети (как «Подключение…» в Telegram).
class ConnectivityStatusBanner extends StatefulWidget {
  const ConnectivityStatusBanner({super.key});

  @override
  State<ConnectivityStatusBanner> createState() =>
      _ConnectivityStatusBannerState();
}

class _ConnectivityStatusBannerState extends State<ConnectivityStatusBanner> {
  bool? _lastHealthy;
  Timer? _recoveredTimer;
  bool _showRecovered = false;

  late final VoidCallback _onStatusChanged;

  @override
  void initState() {
    super.initState();
    _onStatusChanged = _handleStatusChanged;
    FeedSyncService.onlineListenable.addListener(_onStatusChanged);
    ApiReachabilityService.instance.isApiReachable
        .addListener(_onStatusChanged);
    ApiReachabilityService.instance.isApiConnecting
        .addListener(_onStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleStatusChanged();
    });
  }

  @override
  void dispose() {
    _recoveredTimer?.cancel();
    FeedSyncService.onlineListenable.removeListener(_onStatusChanged);
    ApiReachabilityService.instance.isApiReachable
        .removeListener(_onStatusChanged);
    ApiReachabilityService.instance.isApiConnecting
        .removeListener(_onStatusChanged);
    super.dispose();
  }

  bool get _deviceOnline => FeedSyncService.onlineListenable.value;

  bool get _apiReachable => ApiReachabilityService.instance.isApiReachable.value;

  bool get _isHealthy => _deviceOnline && _apiReachable;

  void _handleStatusChanged() {
    if (!mounted) return;

    final healthy = _isHealthy;
    if (_lastHealthy == false && healthy) {
      AppHaptics.light();
      _recoveredTimer?.cancel();
      setState(() => _showRecovered = true);
      _recoveredTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showRecovered = false);
      });
    } else if (!healthy && _lastHealthy == true) {
      AppHaptics.medium();
    }

    if (_lastHealthy != healthy || _showRecovered) {
      setState(() => _lastHealthy = healthy);
    } else {
      _lastHealthy = healthy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_showRecovered && _isHealthy) {
      return _BannerShell(
        color: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        icon: Icons.cloud_done_outlined,
        message: 'Снова в сети',
        textTheme: textTheme,
      );
    }

    if (_isHealthy &&
        !ApiReachabilityService.instance.isApiConnecting.value) {
      return const SizedBox.shrink();
    }

    if (!_deviceOnline) {
      return _BannerShell(
        color: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        icon: Icons.wifi_off_rounded,
        message: 'Ожидание сети…',
        textTheme: textTheme,
        showSpinner: false,
      );
    }

    return _BannerShell(
      color: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      icon: Icons.sync_rounded,
      message: 'Подключение…',
      textTheme: textTheme,
      showSpinner: true,
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
    this.showSpinner = false,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String message;
  final TextTheme textTheme;
  final bool showSpinner;

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              children: [
                if (showSpinner)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
