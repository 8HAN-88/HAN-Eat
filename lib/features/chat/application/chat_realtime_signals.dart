import 'dart:async';

/// Лёгкие сигналы для обновления чатов без WebSocket (push / foreground).
class ChatRealtimeSignals {
  ChatRealtimeSignals._();

  static final ChatRealtimeSignals instance = ChatRealtimeSignals._();

  final _hubRefresh = StreamController<void>.broadcast();
  final _threadPoll = StreamController<void>.broadcast();
  Timer? _debounce;

  Stream<void> get hubRefresh => _hubRefresh.stream;
  Stream<void> get threadPoll => _threadPoll.stream;

  void notifyNewMessage() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_hubRefresh.isClosed) _hubRefresh.add(null);
      if (!_threadPoll.isClosed) _threadPoll.add(null);
    });
  }
}
