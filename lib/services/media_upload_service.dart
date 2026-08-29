// Сервис для загрузки медиа файлов
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../core/network/api_endpoint_resolver.dart';
import '../core/network/api_rate_limit_backoff.dart';
import '../core/network/haneat_http_client.dart';
import '../core/network/weak_net_policy.dart';
import 'auth_service.dart';
import 'server_config.dart';

class MediaUploadService {
  /// URL API — на эмуляторе Android используется 10.0.2.2 (см. ServerConfig)
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Подменить хост в URL на тот, с которого доступен сервер (для эмулятора — 10.0.2.2)
  static String _fixUploadUrl(String uploadUrl) {
    final fixed = ApiEndpointResolver.rewriteProductionHost(uploadUrl);
    final base = ServerConfig.baseUrl;
    final uri = Uri.parse(fixed);
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      final resolved = Uri.parse(base)
          .replace(path: uri.path, query: uri.query, fragment: uri.fragment);
      return resolved.toString();
    }
    return fixed;
  }

  static Future<void> _waitForRateLimit() async {
    final started = DateTime.now();
    while (ApiRateLimitBackoff.isActive) {
      final elapsed = DateTime.now().difference(started);
      if (WeakNetPolicy.shouldStopRateLimitWait(elapsed)) break;
      final remaining =
          ApiRateLimitBackoff.remaining ?? const Duration(seconds: 2);
      final slice = WeakNetPolicy.mediaRateLimitDelay(
        remaining: remaining,
        elapsed: elapsed,
      );
      if (slice <= Duration.zero) break;
      await Future<void>.delayed(slice);
    }
  }

  static void _registerRateLimit(http.Response response) {
    if (response.statusCode != 429) return;
    final retryAfter =
        int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
    ApiRateLimitBackoff.register(retryAfterSeconds: retryAfter);
  }

  static Future<http.Response> _apiPost(
    Uri uri, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _waitForRateLimit();
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    Future<http.Response> run(String authToken) async {
      try {
        return await HanEatHttpClient.withShared(
          (client) => client
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer $authToken',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(body),
              )
              .timeout(timeout),
        );
      } catch (_) {
        HanEatHttpClient.recreateShared();
        await ApiEndpointResolver.revalidateIfNeeded();
        rethrow;
      }
    }

    var response = await run(token);
    if (response.statusCode == 401) {
      try {
        token = await AuthService.refreshToken();
        response = await run(token);
      } catch (e) {
        throw Exception('Authentication failed. Please log in again.');
      }
    }

    _registerRateLimit(response);
    if (response.statusCode == 429) {
      await _waitForRateLimit();
      return _apiPost(uri, body: body, timeout: timeout);
    }
    return response;
  }

  /// Инициализация загрузки (получение presigned URL или API URL)
  static Future<UploadInitResponse> initUpload({
    required String fileType, // 'image', 'video', 'audio' or 'document'
    required String contentType, // 'image/jpeg', 'video/mp4', etc.
    required int fileSize,
    bool preferApiUpload = false,
    String? clientUploadId,
  }) async {
    final uri = Uri.parse('$baseUrl/uploads/init');
    final response = await _apiPost(
      uri,
      body: {
        'file_type': fileType,
        'content_type': contentType,
        'file_size': fileSize,
        'prefer_api': preferApiUpload,
        if (clientUploadId != null) 'client_upload_id': clientUploadId,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UploadInitResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(
          error?['detail'] ?? 'Failed to init upload: ${response.statusCode}');
    }
  }

  static bool _isApiUploadUrl(String url) {
    return url.contains('/uploads/mock/');
  }

  /// Загрузка файла по presigned URL или через API
  static Future<void> uploadFile({
    required String uploadUrl,
    required XFile file,
    required String contentType,
    void Function(int sentBytes, int totalBytes)? onUploadProgress,
  }) async {
    final effectiveUrl = _fixUploadUrl(uploadUrl);
    final contentLength = await file.length();

    final headers = <String, String>{
      'Content-Type': contentType,
      'Content-Length': '$contentLength',
    };

    final viaApi = _isApiUploadUrl(effectiveUrl);
    if (viaApi) {
      final token = await AuthService.getAccessTokenForApi();
      if (token == null) {
        throw Exception('Not authenticated');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _putUploadWithRetries(
      uri: Uri.parse(effectiveUrl),
      headers: headers,
      file: file,
      contentLength: contentLength,
      viaApi: viaApi,
      onUploadProgress: onUploadProgress,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final errorBody = response.body;
      if (errorBody.contains('InvalidAccessKeyId') ||
          errorBody.contains('AWS Access Key')) {
        throw Exception(
          'Хранилище медиа настроено неверно (S3). Обратитесь к администратору или повторите позже.',
        );
      }
      throw Exception(
          'Failed to upload file: ${response.statusCode} - $errorBody');
    }
  }

  static Future<http.Response> _putUpload(
    Uri uri, {
    required Map<String, String> headers,
    required XFile file,
    required int contentLength,
    void Function(int sentBytes, int totalBytes)? onUploadProgress,
  }) async {
    final client = HanEatHttpClient.createUploadClient();
    try {
      final request = http.StreamedRequest('PUT', uri);
      request.headers.addAll(headers);
      request.contentLength = contentLength;
      var sentBytes = 0;
      onUploadProgress?.call(sentBytes, contentLength);
      await for (final chunk in file.openRead()) {
        request.sink.add(chunk);
        sentBytes += chunk.length;
        onUploadProgress?.call(sentBytes, contentLength);
      }
      await request.sink.close();
      final streamed = await client.send(request).timeout(
            const Duration(seconds: 120),
          );
      return http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  static bool _isRetryableUploadError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('timed out') ||
        text.contains('handshakeexception') ||
        text.contains('clientexception');
  }

  static Future<http.Response> _putUploadWithRetries({
    required Uri uri,
    required Map<String, String> headers,
    required XFile file,
    required int contentLength,
    required bool viaApi,
    void Function(int sentBytes, int totalBytes)? onUploadProgress,
  }) async {
    var workingUri = uri;
    var workingHeaders = Map<String, String>.from(headers);
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final response = await _putUpload(
          workingUri,
          headers: workingHeaders,
          file: file,
          contentLength: contentLength,
          onUploadProgress: onUploadProgress,
        );
        if (viaApi && response.statusCode == 401) {
          final refreshedToken = await AuthService.refreshToken();
          workingHeaders['Authorization'] = 'Bearer $refreshedToken';
          continue;
        }
        if ((response.statusCode == 502 ||
                response.statusCode == 503 ||
                response.statusCode == 504) &&
            attempt < 3) {
          await Future<void>.delayed(
              Duration(milliseconds: 350 * (attempt + 1)));
          continue;
        }
        return response;
      } catch (e) {
        lastError = e;
        if (attempt >= 3 || !_isRetryableUploadError(e)) rethrow;
        HanEatHttpClient.recreateShared();
        await ApiEndpointResolver.revalidateIfNeeded();
        workingUri = Uri.parse(_fixUploadUrl(workingUri.toString()));
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw Exception(lastError ?? 'Failed to upload file');
  }

  /// Завершение загрузки
  static Future<UploadCompleteResponse> completeUpload({
    required String uploadId,
    required String fileKey,
    required String fileType,
  }) async {
    final uri = Uri.parse('$baseUrl/uploads/complete');
    final response = await _apiPost(
      uri,
      timeout: const Duration(seconds: 90),
      body: {
        'upload_id': uploadId,
        'file_key': fileKey,
        'file_type': fileType,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UploadCompleteResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? 'Failed to complete upload');
    }
  }

  /// Получить статус обработки
  static Future<UploadStatusResponse> getUploadStatus(String uploadId) async {
    final uri = Uri.parse('$baseUrl/uploads/status/$uploadId');
    final response = await _apiGet(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UploadStatusResponse.fromJson(data);
    } else {
      throw Exception('Failed to get upload status');
    }
  }

  static Future<http.Response> _apiGet(
    Uri uri, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _waitForRateLimit();
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    Future<http.Response> run(String authToken) async {
      try {
        return await HanEatHttpClient.withShared(
          (client) => client.get(
            uri,
            headers: {
              'Authorization': 'Bearer $authToken',
              'Content-Type': 'application/json',
            },
          ).timeout(timeout),
        );
      } catch (_) {
        HanEatHttpClient.recreateShared();
        await ApiEndpointResolver.revalidateIfNeeded();
        rethrow;
      }
    }

    var response = await run(token);
    if (response.statusCode == 401) {
      try {
        token = await AuthService.refreshToken();
        response = await run(token);
      } catch (_) {
        throw Exception('Authentication failed. Please log in again.');
      }
    }
    _registerRateLimit(response);
    if (response.statusCode == 429) {
      await _waitForRateLimit();
      return _apiGet(uri, timeout: timeout);
    }
    return response;
  }

  static Future<UploadCompleteResponse> _uploadMediaFileOnce({
    required XFile file,
    required String fileType,
    Function(double)? onProgress,
    required bool waitForProcessing,
    required bool preferApiUpload,
    String? clientUploadId,
  }) async {
    final filePath = file.path;
    final fileSize = await file.length();
    final contentType = _getContentType(
      filePath,
      fileType,
      fileName: file.name,
    );

    final initResponse = await initUpload(
      fileType: fileType,
      contentType: contentType,
      fileSize: fileSize,
      preferApiUpload: preferApiUpload,
      clientUploadId: clientUploadId,
    );

    onProgress?.call(0.02);

    await uploadFile(
      uploadUrl: initResponse.uploadUrl,
      file: file,
      contentType: contentType,
      onUploadProgress: (sentBytes, totalBytes) {
        final safeTotal = totalBytes <= 0 ? 1 : totalBytes;
        final ratio = (sentBytes / safeTotal).clamp(0.0, 1.0).toDouble();
        onProgress?.call(0.02 + ratio * 0.86);
      },
    );

    onProgress?.call(0.9);

    final completeResponse = await completeUpload(
      uploadId: initResponse.uploadId,
      fileKey: initResponse.fileKey,
      fileType: fileType,
    );

    onProgress?.call(0.94);

    if (waitForProcessing &&
        fileType == 'video' &&
        completeResponse.processing) {
      final uploadId = completeResponse.uploadId;
      if (uploadId != null && uploadId.isNotEmpty) {
        return waitForVideoProcessing(
          uploadId: uploadId,
          fallbackUrl: completeResponse.url,
          onProgress: onProgress,
        );
      }
    }

    return completeResponse;
  }

  /// Полный процесс загрузки (init + upload + complete)
  static Future<UploadCompleteResponse> uploadMediaFile({
    required XFile file,
    required String fileType,
    Function(double)? onProgress,
    bool waitForProcessing = true,
    String? clientUploadId,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await _waitForRateLimit();
        return await _uploadMediaFileOnce(
          file: file,
          fileType: fileType,
          onProgress: onProgress,
          waitForProcessing: waitForProcessing,
          preferApiUpload: true,
          clientUploadId: clientUploadId,
        );
      } catch (e) {
        lastError = e;
        final lower = e.toString().toLowerCase();
        final isRateLimited = lower.contains('too many requests') ||
            lower.contains('rate_limit') ||
            lower.contains('429');
        if (isRateLimited && attempt < 5) {
          await _waitForRateLimit();
          await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw Exception(lastError ?? 'Не удалось загрузить файл');
  }

  /// Дождаться транскодинга (720p/480p) после загрузки видео.
  /// Если обработка не успела или упала — вернёт fallback (оригинал).
  static Future<UploadCompleteResponse> waitForVideoProcessing({
    required String uploadId,
    String? fallbackUrl,
    Duration timeout = const Duration(minutes: 15),
    void Function(double)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getUploadStatus(uploadId);
      final progress = status.progress.clamp(0, 100) / 100.0;
      onProgress?.call(0.94 + progress * 0.06);

      if (status.status == 'completed') {
        final url = status.url ?? status.mp4_720pUrl ?? fallbackUrl;
        return UploadCompleteResponse(
          status: 'completed',
          url: url,
          thumbnailUrl: status.thumbnailUrl,
          processing: false,
          uploadId: uploadId,
        );
      }
      if (status.status == 'failed') {
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    return UploadCompleteResponse(
      status: 'completed',
      url: fallbackUrl,
      thumbnailUrl: null,
      processing: false,
      uploadId: uploadId,
    );
  }

  static String _fileExtension(String filePath, {String? fileName}) {
    for (final source in [fileName, filePath]) {
      if (source == null || source.isEmpty) continue;
      final dot = source.lastIndexOf('.');
      if (dot >= 0 && dot < source.length - 1) {
        return source.substring(dot + 1).toLowerCase();
      }
    }
    return '';
  }

  static String _getContentType(
    String filePath,
    String fileType, {
    String? fileName,
  }) {
    var extension = _fileExtension(filePath, fileName: fileName);
    if (extension.isEmpty) {
      extension = switch (fileType) {
        'video' => 'webm',
        'audio' => 'webm',
        _ => '',
      };
    }

    if (fileType == 'image') {
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    } else if (fileType == 'video') {
      switch (extension) {
        case 'mp4':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        case 'webm':
          return 'video/webm';
        default:
          return 'video/mp4';
      }
    } else if (fileType == 'audio') {
      switch (extension) {
        case 'm4a':
          return 'audio/mp4';
        case 'aac':
          return 'audio/aac';
        case 'mp3':
          return 'audio/mpeg';
        case 'caf':
          return 'audio/x-caf';
        case 'webm':
          return 'audio/webm';
        case 'ogg':
        case 'opus':
          return 'audio/ogg';
        default:
          return 'audio/webm';
      }
    } else if (fileType == 'document') {
      switch (extension) {
        case 'pdf':
          return 'application/pdf';
        case 'txt':
          return 'text/plain';
        case 'doc':
          return 'application/msword';
        case 'docx':
          return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        case 'zip':
          return 'application/zip';
        default:
          return 'application/octet-stream';
      }
    }

    return 'application/octet-stream';
  }
}

class UploadInitResponse {
  final String uploadId;
  final String uploadUrl;
  final String fileKey;
  final int expiresIn;
  final String cdnUrl;

  UploadInitResponse({
    required this.uploadId,
    required this.uploadUrl,
    required this.fileKey,
    required this.expiresIn,
    required this.cdnUrl,
  });

  factory UploadInitResponse.fromJson(Map<String, dynamic> json) {
    return UploadInitResponse(
      uploadId: json['upload_id'] as String,
      uploadUrl: json['upload_url'] as String,
      fileKey: json['file_key'] as String,
      expiresIn: json['expires_in'] as int,
      cdnUrl: json['cdn_url'] as String,
    );
  }
}

class UploadCompleteResponse {
  final String status;
  final String? url;
  final String? thumbnailUrl;
  final bool processing;
  final String? uploadId;

  UploadCompleteResponse({
    required this.status,
    this.url,
    this.thumbnailUrl,
    required this.processing,
    this.uploadId,
  });

  factory UploadCompleteResponse.fromJson(Map<String, dynamic> json) {
    return UploadCompleteResponse(
      status: json['status'] as String,
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      processing: json['processing'] as bool? ?? false,
      uploadId: json['upload_id'] as String?,
    );
  }
}

class UploadStatusResponse {
  final String status;
  final double progress;
  final String? url;
  final String? mp4_720pUrl;
  final String? mp4_480pUrl;
  final String? mp4_1080pUrl;
  final String? hlsUrl;
  final String? thumbnailUrl;

  UploadStatusResponse({
    required this.status,
    required this.progress,
    this.url,
    this.mp4_720pUrl,
    this.mp4_480pUrl,
    this.mp4_1080pUrl,
    this.hlsUrl,
    this.thumbnailUrl,
  });

  factory UploadStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    final progress = rawProgress is num ? rawProgress.toDouble() : 0.0;
    return UploadStatusResponse(
      status: json['status'] as String,
      progress: progress,
      url: json['url'] as String?,
      mp4_720pUrl: json['mp4_720p_url'] as String?,
      mp4_480pUrl: json['mp4_480p_url'] as String?,
      mp4_1080pUrl: json['mp4_1080p_url'] as String?,
      hlsUrl: json['hls_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}
