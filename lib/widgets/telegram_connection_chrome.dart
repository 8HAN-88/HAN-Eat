import 'package:flutter/material.dart';

import '../core/network/telegram_connection_status.dart';
import '../services/api_reachability_service.dart';
import '../services/auth_service.dart';
import '../services/feed_sync_service.dart';
import '../services/user_realtime_service.dart';

/// Живые сигналы для шапки «Ожидание сети / Соединение / Обновление».
class TelegramConnectionChrome {
  const TelegramConnectionChrome._();

  static Listenable? _cached;

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
    return TelegramConnectionStatus.resolve(
      deviceOnline: FeedSyncService.onlineListenable.value,
      apiReachable: ApiReachabilityService.instance.isApiReachable.value,
      apiConnecting: ApiReachabilityService.instance.isApiConnecting.value,
      realtimeConnected: UserRealtimeService.instance.connected.value,
      signedIn: AuthService.instance.currentUser != null,
    );
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
