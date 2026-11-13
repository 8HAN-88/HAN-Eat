import 'dart:typed_data';

/// Bytes captured in the browser from the microphone or camera.
class CapturedClip {
  const CapturedClip({
    required this.bytes,
    required this.mimeType,
    required this.filename,
    required this.durationSec,
  });

  final Uint8List bytes;
  final String mimeType;
  final String filename;
  final int durationSec;
}

const audioMimeCandidates = <String>[
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4',
  'audio/aac',
];

const videoMimeCandidates = <String>[
  'video/webm;codecs=vp8,opus',
  'video/webm;codecs=vp9,opus',
  'video/webm',
  'video/mp4',
];

/// First type [supported] accepts. Null means the browser should pick.
String? firstSupportedMime(
  List<String> types,
  bool Function(String type) supported,
) {
  for (final type in types) {
    if (supported(type)) return type;
  }
  return null;
}

String extensionForMime(String mime, {required bool video}) {
  final base = mime.split(';').first.trim().toLowerCase();
  if (base.contains('wav')) return 'wav';
  if (base.contains('ogg')) return 'ogg';
  if (base.contains('mp4') || base.contains('aac') || base.contains('m4a')) {
    return video ? 'mp4' : 'm4a';
  }
  return 'webm';
}
