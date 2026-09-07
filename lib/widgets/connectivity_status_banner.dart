import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptics/app_haptics.dart';
import '../core/network/telegram_connection_status.dart';
import 'telegram_connection_chrome.dart';

/// Полоска сверху, как статус в шапке Telegram.
class ConnectivityStatusBanner extends StatefulWidget {
  const ConnectivityStatusBanner({super.key});

  /// Пока полоска на экране, нижние экраны не должны повторно есть SafeArea.
  static final ValueNotifier<bool> occupiesTop = ValueNotifier(false);

  @override
  State<ConnectivityStatusBanner> createState() =>
      _ConnectivityStatusBannerState();
}

class _ConnectivityStatusBannerState extends State<ConnectivityStatusBanner> {
  TelegramConnectionPhase? _lastPhase;
  Timer? _recoveredTimer;
  bool _showRecovered = false;

  late final Listenable _listenable;
  late final VoidCallback _onStatusChanged;

  @override
  void initState() {
    super.initState();
    _listenable = TelegramConnectionChrome.listenable();
    _onStatusChanged = _handleStatusChanged;
    _listenable.addListener(_onStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleStatusChanged();
    });
  }

  @override
  void dispose() {
    _recoveredTimer?.cancel();
    _listenable.removeListener(_onStatusChanged);
    if (ConnectivityStatusBanner.occupiesTop.value) {
      ConnectivityStatusBanner.occupiesTop.value = false;
    }
    super.dispose();
  }

  TelegramConnectionPhase get _phase => TelegramConnectionChrome.phase();

  void _scheduleOccupiesTop(bool occupy) {
    if (ConnectivityStatusBanner.occupiesTop.value == occupy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ConnectivityStatusBanner.occupiesTop.value != occupy) {
        ConnectivityStatusBanner.occupiesTop.value = occupy;
      }
    });
  }

  void _handleStatusChanged() {
    if (!mounted) return;

    final phase = _phase;
    final wasTrouble =
        _lastPhase != null && _lastPhase != TelegramConnectionPhase.ok;
    if (wasTrouble && phase == TelegramConnectionPhase.ok) {
      AppHaptics.light();
      _recoveredTimer?.cancel();
      setState(() => _showRecovered = true);
      _recoveredTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showRecovered = false);
      });
    } else if (phase != TelegramConnectionPhase.ok &&
        _lastPhase == TelegramConnectionPhase.ok) {
      AppHaptics.medium();
    }

    if (_lastPhase != phase || _showRecovered) {
      setState(() => _lastPhase = phase);
    } else {
      _lastPhase = phase;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final phase = _phase;

    if (_showRecovered && phase == TelegramConnectionPhase.ok) {
      _scheduleOccupiesTop(true);
      return _BannerShell(
        color: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        icon: Icons.cloud_done_outlined,
        message: 'Снова в сети',
        textTheme: textTheme,
      );
    }

    final message = TelegramConnectionStatus.labelFor(phase);
    if (message == null) {
      _scheduleOccupiesTop(false);
      return const SizedBox.shrink();
    }

    _scheduleOccupiesTop(true);
    final waiting = phase == TelegramConnectionPhase.waitingNetwork;
    return _BannerShell(
      color: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      icon: waiting ? Icons.wifi_off_rounded : Icons.sync_rounded,
      message: message,
      textTheme: textTheme,
      showSpinner: !waiting,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                Flexible(
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
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
