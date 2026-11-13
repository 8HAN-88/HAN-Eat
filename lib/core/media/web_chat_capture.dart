import 'web_chat_capture_stub.dart'
    if (dart.library.html) 'web_chat_capture_web.dart' as impl;

import 'captured_clip.dart';

export 'captured_clip.dart';

/// Starts the microphone inside the tap, before any later await.
void armWebVoice() => impl.armWebVoice();

Future<void> awaitWebVoice() => impl.awaitWebVoice();

Future<CapturedClip> stopWebVoice() => impl.stopWebVoice();

Future<void> cancelWebVoice() => impl.cancelWebVoice();

/// Starts the camera inside the tap. Call again from [finishWebVideoNote].
void armWebVideoNote() => impl.armWebVideoNote();

Future<CapturedClip?> finishWebVideoNote() => impl.finishWebVideoNote();
