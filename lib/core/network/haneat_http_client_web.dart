import 'package:http/http.dart' as http;

http.Client? _webInstance;

http.Client createHanEatHttpClient() {
  return _webInstance ??= http.Client();
}

http.Client createHanEatStreamClient() => http.Client();

void resetHanEatHttpClientForTest() {
  _webInstance = null;
}

http.Client createHanEatUploadClient() => http.Client();

