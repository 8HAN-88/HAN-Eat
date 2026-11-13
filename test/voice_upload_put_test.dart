import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/media_upload_service.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('voice upload finishes after the body is buffered', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(48 * 1024, (i) => i % 251),
    );
    final received = <int>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
    addTearDown(server.close);
    server.listen((request) async {
      await for (final chunk in request) {
        received.addAll(chunk);
      }
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });

    final file = XFile.fromData(
      payload,
      name: 'voice.webm',
      mimeType: 'audio/webm',
    );
    await MediaUploadService.uploadFile(
      uploadUrl: 'http://[::1]:${server.port}/voice',
      file: file,
      contentType: 'audio/webm',
    ).timeout(const Duration(seconds: 5));

    expect(received, payload);
  });
}
