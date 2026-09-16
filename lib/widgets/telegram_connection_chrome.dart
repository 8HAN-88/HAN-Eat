import 'package:flutter/material.dart';

import '../core/network/cold_start_policy.dart';
import '../core/network/telegram_connection_status.dart';
import '../services/api_reachability_service.dart';
import '../services/auth_service.dart';
import '../services/feed_sync_service.dart';
import '../services/user_realtime_service.dart';

/// Живые сигналы для шапки «Ожидание сети / Соединение / Обновление».
class TelegramConnectionChrome {
  const TelegramConnectionChrome._();

  static Listenable? _cached;
  static DateTime? _updatingSince;

  static Listenable listenable() {
    if (_cached != null) return _cached!;
    final sources = <Listenable>[
      ApiReachabilityService.instance.isApiReachable,
      ApiReachabilityService.instance.isApiConnecting,
      UserRealtimeService.instance.connected,
      AuthService.sessionRevision,
    ];
    try {
      sources.insert(0, FeedSyncService.instance.isOnline);
      _cached = Listenable.merge(sources);
      return _cached!;
    } catch (_) {
      return Listenable.merge([
        FeedSyncService.onlineListenable,
        ...sources,
      ]);
    }
  }

  static TelegramConnectionPhase phase() {
    final realtimeConnected = UserRealtimeService.instance.connected.value;
    final raw = TelegramConnectionStatus.resolve(
      deviceOnline: FeedSyncService.onlineListenable.value,
      apiReachable: ApiReachabilityService.instance.isApiReachable.value,
      apiConnecting: ApiReachabilityService.instance.isApiConnecting.value,
      realtimeConnected: realtimeConnected,
      signedIn: AuthService.instance.currentUser != null,
    );
    if (raw == TelegramConnectionPhase.updating) {
      _updatingSince ??= DateTime.now();
      final waited = DateTime.now().difference(_updatingSince!);
      if (waited >= ColdStartPolicy.updatingChromeMax) {
        return TelegramConnectionStatus.resolve(
          deviceOnline: FeedSyncService.onlineListenable.value,
          apiReachable: ApiReachabilityService.instance.isApiReachable.value,
          apiConnecting: ApiReachabilityService.instance.isApiConnecting.value,
          realtimeConnected: realtimeConnected,
          signedIn: AuthService.instance.currentUser != null,
          realtimeWaitExpired: true,
        );
      }
    } else {
      _updatingSince = null;
    }
    return raw;
  }

  static String? label() => TelegramConnectionStatus.labelFor(phase());
}

/// Заголовок как в Telegram: при обрыве вместо «Сообщения» пишется статус.
class TelegramConnectionAwareTitle extends StatefulWidget {
  const TelegramConnectionAwareTitle({
    super.key,
    required this.fallback,
    this.style,
    this.maxLines = 1,
  });

  final String fallback;
  final TextStyle? style;
  final int maxLines;

  @override
  State<TelegramConnectionAwareTitle> createState() =>
      _TelegramConnectionAwareTitleState();
}

class _TelegramConnectionAwareTitleState
    extends State<TelegramConnectionAwareTitle> {
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();
    _listenable = TelegramConnectionChrome.listenable();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final label = TelegramConnectionChrome.label() ?? widget.fallback;
        if (label.isEmpty) {
          return const SizedBox.shrink();
        }
        final connecting = TelegramConnectionStatus.isConnectionLabel(label);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Text(
            label,
            key: ValueKey<String>(label),
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
            style: (widget.style ?? DefaultTextStyle.of(context).style).copyWith(
              color: connecting
                  ? Theme.of(context).colorScheme.primary
                  : widget.style?.color,
            ),
          ),
        );
      },
    );
  }
}
