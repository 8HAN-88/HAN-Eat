import 'package:flutter/foundation.dart';

/// Exclusive voice / video-note playback across chat bubbles.
///
/// Ensures only one media source plays at a time and supports
/// Telegram-style autoplay of the next voice message.
class ChatVoicePlaybackCoordinator extends ChangeNotifier {
  ChatVoicePlaybackCoordinator._();
  static final ChatVoicePlaybackCoordinator instance =
      ChatVoicePlaybackCoordinator._();

  Object? _owner;
  VoidCallback? _onStolen;
  int? _requestedPlayMessageId;

  int? get requestedPlayMessageId => _requestedPlayMessageId;

  /// Claim exclusive playback for [owner]. Previous owner is stopped.
  void claim(Object owner, {required VoidCallback onStolen}) {
    if (identical(_owner, owner)) {
      _onStolen = onStolen;
      return;
    }
    final previous = _onStolen;
    _owner = owner;
    _onStolen = onStolen;
    previous?.call();
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onStolen = null;
  }

  void stopAll() {
    final previous = _onStolen;
    _owner = null;
    _onStolen = null;
    previous?.call();
  }

  /// Ask the bubble for [messageId] to start playing (e.g. play-next).
  void requestPlay(int messageId) {
    if (messageId <= 0) return;
    _requestedPlayMessageId = messageId;
    notifyListeners();
  }

  void clearRequest(int messageId) {
    if (_requestedPlayMessageId == messageId) {
      _requestedPlayMessageId = null;
    }
  }
}
