// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// PUT с прогрессом `xhr.upload`. Проценты идут по байтам в сети,
/// а не по локальному буферу, который для кружка заполняется сразу.
Future<http.Response> putUploadBytes({
  required Uri uri,
  required Map<String, String> headers,
  required List<int> bytes,
  void Function(int sentBytes, int totalBytes)? onUploadProgress,
}) {
  final completer = Completer<http.Response>();
  final xhr = html.HttpRequest();
  xhr.open('PUT', uri.toString());
  xhr.timeout = 120000;
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'content-length') return;
    xhr.setRequestHeader(key, value);
  });
  final total = bytes.length;
  xhr.upload.onProgress.listen((html.ProgressEvent event) {
    final reportedTotal = event.lengthComputable ? (event.total ?? total) : total;
    final loaded = event.loaded ?? 0;
    onUploadProgress?.call(loaded, reportedTotal <= 0 ? 1 : reportedTotal);
  });
  xhr.onLoad.listen((_) {
    if (completer.isCompleted) return;
    completer.complete(
      http.Response(xhr.responseText ?? '', xhr.status ?? 0),
    );
  });
  xhr.onError.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(Exception('Не удалось загрузить файл'));
  });
  xhr.onTimeout.listen((_) {
    if (completer.isCompleted) return;
    xhr.abort();
    completer.completeError(TimeoutException('timeout'));
  });
  onUploadProgress?.call(0, total <= 0 ? 1 : total);
  xhr.send(Uint8List.fromList(bytes));
  return completer.future;
}
