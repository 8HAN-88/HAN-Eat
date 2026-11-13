// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'captured_clip.dart';

html.MediaStream? _voiceStream;
html.MediaRecorder? _voiceRecorder;
List<html.Blob> _voiceChunks = <html.Blob>[];
Future<html.MediaStream>? _voiceReady;
DateTime? _voiceStarted;

html.MediaStream? _noteStream;
Future<html.MediaStream>? _noteReady;
html.DivElement? _noteOverlay;

void armWebVoice() {
  unawaited(cancelWebVoice());
  final devices = html.window.navigator.mediaDevices;
  if (devices == null) {
    _voiceReady = Future<html.MediaStream>.error(
      Exception('Микрофон недоступен в этом браузере'),
    );
    return;
  }
  // Must be invoked in the tap turn. Awaiting first loses the Safari gesture.
  _voiceReady = devices.getUserMedia(<String, dynamic>{'audio': true});
  _voiceStarted = DateTime.now();
}

Future<void> awaitWebVoice() async {
  final pending = _voiceReady;
  if (pending == null) {
    throw Exception('Микрофон не запущен');
  }
  final stream = await pending;
  _voiceStream = stream;
  final mime = firstSupportedMime(
    audioMimeCandidates,
    html.MediaRecorder.isTypeSupported,
  );
  final recorder = mime == null
      ? html.MediaRecorder(stream)
      : html.MediaRecorder(stream, <String, dynamic>{'mimeType': mime});
  _voiceChunks = <html.Blob>[];
  recorder.addEventListener('dataavailable', (html.Event event) {
    if (event is html.BlobEvent) {
      final blob = event.data;
      if (blob != null && blob.size > 0) _voiceChunks.add(blob);
    }
  });
  recorder.start(200);
  _voiceRecorder = recorder;
  _voiceStarted ??= DateTime.now();
}

Future<CapturedClip> stopWebVoice() async {
  final recorder = _voiceRecorder;
  final started = _voiceStarted ?? DateTime.now();
  if (recorder == null) {
    await cancelWebVoice();
    throw Exception('Не удалось сохранить запись');
  }
  final blob = await _stopRecorder(recorder, _voiceChunks);
  final seconds = DateTime.now().difference(started).inSeconds;
  await cancelWebVoice();
  final bytes = await _readBlob(blob);
  if (bytes.isEmpty) {
    throw Exception('Пустая запись');
  }
  final recorded = blob.type.trim();
  final fromRecorder = (recorder.mimeType ?? '').trim();
  final mime = recorded.isNotEmpty
      ? recorded
      : (fromRecorder.isNotEmpty ? fromRecorder : 'audio/webm');
  final ext = extensionForMime(mime, video: false);
  return CapturedClip(
    bytes: bytes,
    mimeType: mime,
    filename: 'voice_${started.millisecondsSinceEpoch}.$ext',
    durationSec: seconds < 1 ? 1 : seconds,
  );
}

Future<void> cancelWebVoice() async {
  final recorder = _voiceRecorder;
  _voiceRecorder = null;
  _voiceChunks = <html.Blob>[];
  _voiceReady = null;
  _voiceStarted = null;
  try {
    if (recorder != null && recorder.state == 'recording') {
      recorder.stop();
    }
  } catch (_) {}
  _stopStream(_voiceStream);
  _voiceStream = null;
}

void armWebVideoNote() {
  _discardVideoNote();
  final devices = html.window.navigator.mediaDevices;
  if (devices == null) {
    _noteReady = Future<html.MediaStream>.error(
      Exception('Камера недоступна в этом браузере'),
    );
    return;
  }
  _noteReady = devices.getUserMedia(<String, dynamic>{
    'audio': true,
    'video': <String, dynamic>{
      'facingMode': 'user',
      'width': <String, dynamic>{'ideal': 640},
      'height': <String, dynamic>{'ideal': 640},
    },
  });
}

Future<CapturedClip?> finishWebVideoNote() async {
  final pending = _noteReady;
  if (pending == null) {
    armWebVideoNote();
  }
  final ready = _noteReady;
  if (ready == null) return null;
  html.MediaStream stream;
  try {
    stream = await ready;
  } catch (_) {
    _discardVideoNote();
    throw Exception('Разрешите доступ к камере и микрофону');
  }
  _noteStream = stream;
  final started = DateTime.now();
  final mime = firstSupportedMime(
    videoMimeCandidates,
    html.MediaRecorder.isTypeSupported,
  );
  final recorder = html.MediaRecorder(stream, <String, dynamic>{
    if (mime != null) 'mimeType': mime,
    'videoBitsPerSecond': 900000,
    'audioBitsPerSecond': 64000,
  });
  final chunks = <html.Blob>[];
  recorder.addEventListener('dataavailable', (html.Event event) {
    if (event is html.BlobEvent) {
      final blob = event.data;
      if (blob != null && blob.size > 0) chunks.add(blob);
    }
  });
  final done = Completer<CapturedClip?>();
  Timer? tick;
  Timer? limit;
  late final html.DivElement overlay;

  void close([CapturedClip? clip]) {
    if (done.isCompleted) return;
    tick?.cancel();
    limit?.cancel();
    overlay.remove();
    _noteOverlay = null;
    done.complete(clip);
  }

  Future<void> finish() async {
    try {
      final blob = await _stopRecorder(recorder, chunks);
      final bytes = await _readBlob(blob);
      _stopStream(stream);
      _noteStream = null;
      _noteReady = null;
      if (bytes.isEmpty) {
        close(null);
        return;
      }
      final recorded = blob.type.trim();
      final fromRecorder = (recorder.mimeType ?? '').trim();
      final type = recorded.isNotEmpty
          ? recorded
          : (fromRecorder.isNotEmpty ? fromRecorder : 'video/webm');
      final ext = extensionForMime(type, video: true);
      final seconds = DateTime.now().difference(started).inSeconds;
      close(
        CapturedClip(
          bytes: bytes,
          mimeType: type,
          filename: 'note_${started.millisecondsSinceEpoch}.$ext',
          durationSec: seconds < 1 ? 1 : seconds,
        ),
      );
    } catch (_) {
      _stopStream(stream);
      _noteStream = null;
      _noteReady = null;
      close(null);
    }
  }

  overlay = _buildNoteOverlay(
    stream: stream,
    onCancel: () {
      try {
        if (recorder.state == 'recording') recorder.stop();
      } catch (_) {}
      _stopStream(stream);
      _noteStream = null;
      _noteReady = null;
      close(null);
    },
    onStop: () => unawaited(finish()),
  );
  html.document.body?.append(overlay);
  _noteOverlay = overlay;
  final timerEl = overlay.querySelector('.han-note-timer');
  recorder.start(200);
  tick = Timer.periodic(const Duration(seconds: 1), (_) {
    final seconds = DateTime.now().difference(started).inSeconds;
    if (timerEl != null) {
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      timerEl.text = '$m:$s';
    }
  });
  limit = Timer(const Duration(seconds: 60), () => unawaited(finish()));
  return done.future;
}

void _discardVideoNote() {
  _noteOverlay?.remove();
  _noteOverlay = null;
  _stopStream(_noteStream);
  _noteStream = null;
  _noteReady = null;
}

html.DivElement _buildNoteOverlay({
  required html.MediaStream stream,
  required void Function() onCancel,
  required void Function() onStop,
}) {
  final overlay = html.DivElement()
    ..style.position = 'fixed'
    ..style.top = '0'
    ..style.left = '0'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.zIndex = '2147483000'
    ..style.backgroundColor = '#0F1319'
    ..style.display = 'flex'
    ..style.flexDirection = 'column'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center'
    ..style.gap = '20px'
    ..style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';

  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..style.width = '240px'
    ..style.height = '240px'
    ..style.borderRadius = '50%'
    ..style.objectFit = 'cover'
    ..style.backgroundColor = '#1A212B'
    ..style.transform = 'scaleX(-1)';
  video.srcObject = stream;

  final timer = html.DivElement()
    ..className = 'han-note-timer'
    ..text = '00:00'
    ..style.color = '#F7F8FA'
    ..style.fontSize = '20px'
    ..style.fontWeight = '600';

  html.ButtonElement button(String label, String color, void Function() tap) {
    return html.ButtonElement()
      ..text = label
      ..type = 'button'
      ..style.border = '0'
      ..style.borderRadius = '999px'
      ..style.padding = '12px 22px'
      ..style.fontSize = '16px'
      ..style.fontWeight = '600'
      ..style.color = '#fff'
      ..style.backgroundColor = color
      ..onClick.listen((event) {
        event.preventDefault();
        tap();
      });
  }

  final row = html.DivElement()
    ..style.display = 'flex'
    ..style.gap = '12px'
    ..append(button('Отмена', '#3A4454', onCancel))
    ..append(button('Отправить', '#FF6B35', onStop));

  overlay
    ..append(video)
    ..append(timer)
    ..append(row);
  unawaited(video.play());
  return overlay;
}

Future<html.Blob> _stopRecorder(
  html.MediaRecorder recorder,
  List<html.Blob> chunks,
) {
  final completer = Completer<html.Blob>();
  void complete() {
    if (completer.isCompleted) return;
    final type = recorder.mimeType;
    completer.complete(html.Blob(chunks, type ?? ''));
  }

  recorder.addEventListener('stop', (_) => complete());
  try {
    if (recorder.state == 'recording') {
      recorder.stop();
    } else {
      complete();
    }
  } catch (_) {
    complete();
  }
  return completer.future.timeout(
    const Duration(seconds: 3),
    onTimeout: () {
      complete();
      return html.Blob(chunks, recorder.mimeType ?? '');
    },
  );
}

Future<Uint8List> _readBlob(html.Blob blob) {
  final reader = html.FileReader();
  final done = Completer<Uint8List>();
  reader.onLoad.listen((_) {
    final result = reader.result;
    if (result is Uint8List) {
      done.complete(result);
    } else if (result is ByteBuffer) {
      done.complete(Uint8List.view(result));
    } else {
      done.complete(Uint8List(0));
    }
  });
  reader.onError.listen((_) {
    if (!done.isCompleted) done.complete(Uint8List(0));
  });
  reader.readAsArrayBuffer(blob);
  return done.future;
}

void _stopStream(html.MediaStream? stream) {
  if (stream == null) return;
  for (final track in stream.getTracks()) {
    try {
      track.stop();
    } catch (_) {}
  }
}
