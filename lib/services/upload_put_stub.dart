import 'package:http/http.dart' as http;

Future<http.Response> putUploadBytes({
  required Uri uri,
  required Map<String, String> headers,
  required List<int> bytes,
  void Function(int sentBytes, int totalBytes)? onUploadProgress,
}) {
  throw UnsupportedError('Загрузка через браузер доступна только в web');
}
