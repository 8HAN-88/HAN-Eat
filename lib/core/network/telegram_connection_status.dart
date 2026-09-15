/// Статусы шапки как в Telegram: сеть → соединение → обновление → обычный заголовок.
enum TelegramConnectionPhase {
  ok,
  waitingNetwork,
  connecting,
  updating,
}

/// Общая лестница для заголовков главных разделов и подзаголовка треда.
class TelegramConnectionStatus {
  const TelegramConnectionStatus._();

  static const waitingNetworkLabel = 'Ожидание сети…';
  static const connectingLabel = 'Соединение…';
  static const updatingLabel = 'Обновление…';

  static TelegramConnectionPhase resolve({
    required bool deviceOnline,
    required bool apiReachable,
    required bool apiConnecting,
    required bool realtimeConnected,
    bool signedIn = true,
  }) {
    if (!deviceOnline) {
      return TelegramConnectionPhase.waitingNetwork;
    }
    if (!apiReachable || apiConnecting) {
      return TelegramConnectionPhase.connecting;
    }
    if (signedIn && !realtimeConnected) {
      return TelegramConnectionPhase.updating;
    }
    return TelegramConnectionPhase.ok;
  }

  static String? labelFor(TelegramConnectionPhase phase) {
    switch (phase) {
      case TelegramConnectionPhase.waitingNetwork:
        return waitingNetworkLabel;
      case TelegramConnectionPhase.connecting:
        return connectingLabel;
      case TelegramConnectionPhase.updating:
        return updatingLabel;
      case TelegramConnectionPhase.ok:
        return null;
    }
  }

  static bool isConnectionLabel(String text) {
    return text == waitingNetworkLabel ||
        text == connectingLabel ||
        text == updatingLabel ||
        text == 'соединение…' ||
        text == 'обновление…';
  }
}
