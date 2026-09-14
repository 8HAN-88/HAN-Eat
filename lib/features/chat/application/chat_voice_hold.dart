/// Hold-to-record voice notes. Finger-up often happens before the
/// recorder is ready (permission / Safari), so we remember send vs cancel.
enum ChatVoiceHoldAction { none, send, cancel }

class ChatVoiceHoldSession {
  bool holdActive = false;
  bool recording = false;
  ChatVoiceHoldAction pending = ChatVoiceHoldAction.none;

  void beginHold() {
    holdActive = true;
    pending = ChatVoiceHoldAction.none;
  }

  /// Finger up or gesture cancel. Locked recording stays open.
  ChatVoiceHoldAction release({
    required bool cancelled,
    required bool locked,
  }) {
    holdActive = false;
    if (locked) return ChatVoiceHoldAction.none;
    final action =
        cancelled ? ChatVoiceHoldAction.cancel : ChatVoiceHoldAction.send;
    if (!recording) {
      pending = action;
      return ChatVoiceHoldAction.none;
    }
    return action;
  }

  bool get shouldStartAfterPermission =>
      holdActive || pending == ChatVoiceHoldAction.send;

  ChatVoiceHoldAction onRecorderStarted() {
    recording = true;
    if (holdActive) return ChatVoiceHoldAction.none;
    final action = pending == ChatVoiceHoldAction.none
        ? ChatVoiceHoldAction.send
        : pending;
    pending = ChatVoiceHoldAction.none;
    return action;
  }

  void reset() {
    holdActive = false;
    recording = false;
    pending = ChatVoiceHoldAction.none;
  }
}
