import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Уже сжатое JPEG с меню/камеры — повторно не трогаем.
bool isLikelyPreparedForAiScan(Uint8List bytes) =>
    bytes.length <= 400 * 1024;

/// Сжатие и уменьшение фото перед AI: длинная сторона не больше [maxSide], JPEG.
Future<Uint8List> prepareImageForAiScan(
  Uint8List bytes, {
  int maxSide = 1024,
  int quality = 78,
}) async {
  if (isLikelyPreparedForAiScan(bytes)) {
    return bytes;
  }
  return Isolate.run(() async {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxSide,
      minHeight: maxSide,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    return Uint8List.fromList(out);
  });
}
