import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/network/telegram_connection_status.dart';

void main() {
  test('offline device is waiting for network', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: false,
        apiReachable: false,
        apiConnecting: false,
        realtimeConnected: false,
      ),
      TelegramConnectionPhase.waitingNetwork,
    );
    expect(
      TelegramConnectionStatus.labelFor(
        TelegramConnectionPhase.waitingNetwork,
      ),
      'Ожидание сети…',
    );
  });

  test('online but API down is connecting', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: false,
        apiConnecting: true,
        realtimeConnected: false,
      ),
      TelegramConnectionPhase.connecting,
    );
    expect(
      TelegramConnectionStatus.labelFor(TelegramConnectionPhase.connecting),
      'Соединение…',
    );
  });

  test('API up and connecting flag still shows connecting', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: true,
        apiConnecting: true,
        realtimeConnected: false,
      ),
      TelegramConnectionPhase.connecting,
    );
  });

  test('API up but realtime wait expired is ok', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: true,
        apiConnecting: false,
        realtimeConnected: false,
        realtimeWaitExpired: true,
      ),
      TelegramConnectionPhase.ok,
    );
  });

  test('API up but realtime catching up is updating', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: true,
        apiConnecting: false,
        realtimeConnected: false,
      ),
      TelegramConnectionPhase.updating,
    );
    expect(
      TelegramConnectionStatus.labelFor(TelegramConnectionPhase.updating),
      'Обновление…',
    );
  });

  test('signed-out user does not show updating', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: true,
        apiConnecting: false,
        realtimeConnected: false,
        signedIn: false,
      ),
      TelegramConnectionPhase.ok,
    );
  });

  test('healthy connection hides the chrome', () {
    expect(
      TelegramConnectionStatus.resolve(
        deviceOnline: true,
        apiReachable: true,
        apiConnecting: false,
        realtimeConnected: true,
      ),
      TelegramConnectionPhase.ok,
    );
    expect(
      TelegramConnectionStatus.labelFor(TelegramConnectionPhase.ok),
      isNull,
    );
  });

  test('connection labels include legacy lowercase chat copy', () {
    expect(TelegramConnectionStatus.isConnectionLabel('Соединение…'), isTrue);
    expect(TelegramConnectionStatus.isConnectionLabel('соединение…'), isTrue);
    expect(TelegramConnectionStatus.isConnectionLabel('в сети'), isFalse);
  });
}
