import 'captured_clip.dart';

void armWebVoice() {}

Future<void> awaitWebVoice() async {}

Future<CapturedClip> stopWebVoice() {
  throw UnsupportedError('Запись в браузере недоступна');
}

Future<void> cancelWebVoice() async {}

void armWebVideoNote() {}

Future<CapturedClip?> finishWebVideoNote() async => null;
