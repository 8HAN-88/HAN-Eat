import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/media/captured_clip.dart';

void main() {
  test('picks the first supported recorder mime', () {
    expect(
      firstSupportedMime(
        audioMimeCandidates,
        (type) => type == 'audio/mp4',
      ),
      'audio/mp4',
    );
    expect(
      firstSupportedMime(videoMimeCandidates, (_) => false),
      isNull,
    );
  });

  test('maps recorder mime to a file extension', () {
    expect(extensionForMime('audio/mp4', video: false), 'm4a');
    expect(extensionForMime('audio/webm;codecs=opus', video: false), 'webm');
    expect(extensionForMime('video/mp4', video: true), 'mp4');
    expect(extensionForMime('audio/wav', video: false), 'wav');
  });
}
