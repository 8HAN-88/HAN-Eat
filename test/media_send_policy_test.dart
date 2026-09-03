import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/network/weak_net_policy.dart';
import 'package:han_eat/features/chat/application/media_send_policy.dart';
import 'package:han_eat/services/chat_media_outbox_service.dart';

void main() {
  test('keeps photo and voice queued on network errors', () {
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: Exception('SocketException: Connection reset'),
        apiReachable: true,
      ),
      isTrue,
    );
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: TimeoutException('upload'),
        apiReachable: true,
      ),
      isTrue,
    );
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: Exception('ClientException: XMLHttpRequest'),
        apiReachable: true,
      ),
      isTrue,
    );
  });

  test('keeps queued while API is down even for unknown errors', () {
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: Exception('unexpected'),
        apiReachable: false,
      ),
      isTrue,
    );
  });

  test('does not keep queued for stars or validation', () {
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: Exception('Недостаточно звёзд'),
        apiReachable: true,
      ),
      isFalse,
    );
    expect(
      MediaSendPolicy.shouldKeepQueued(
        error: Exception('Failed to init upload: 400'),
        apiReachable: true,
      ),
      isFalse,
    );
  });

  test('voice and photo share the same retry budget', () {
    expect(MediaSendPolicy.maxAttempts, 8);
    expect(
      MediaSendPolicy.uploadTimeout(largeFile: false),
      WeakNetPolicy.mediaUploadTimeout,
    );
    expect(
      MediaSendPolicy.retryWaitSeconds(attempts: 1, apiReachable: true),
      2,
    );
    expect(
      MediaSendPolicy.retryWaitSeconds(attempts: 8, apiReachable: false),
      MediaSendPolicy.unreachablePoll.inSeconds,
    );
  });

  test('outbox keeps typical photo and voice, drops empty and huge', () {
    expect(ChatMediaOutboxService.acceptsBytes(240 * 1024), isTrue);
    expect(ChatMediaOutboxService.acceptsBytes(3 * 1024 * 1024), isTrue);
    expect(ChatMediaOutboxService.acceptsBytes(0), isFalse);
    expect(
      ChatMediaOutboxService.acceptsBytes(
        ChatMediaOutboxService.maxBytesPerItem + 1,
      ),
      isFalse,
    );
  });

  test('transport detector covers 429 and timeouts', () {
    expect(
      WeakNetPolicy.isRetryableTransportError(Exception('429 Too Many')),
      isTrue,
    );
    expect(
      WeakNetPolicy.isRetryableTransportError(Exception('stars required')),
      isFalse,
    );
  });
}
