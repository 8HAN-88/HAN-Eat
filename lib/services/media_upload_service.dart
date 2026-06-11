// Сервис для загрузки медиа файлов
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
import 'server_config.dart';

class MediaUploadService {
  /// URL API — на эмуляторе Android используется 10.0.2.2 (см. ServerConfig)
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Подменить хост в URL на тот, с которого доступен сервер (для эмулятора — 10.0.2.2)
  static String _fixUploadUrl(String uploadUrl) {
    final base = ServerConfig.baseUrl;
    final uri = Uri.parse(uploadUrl);
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      final fixed = Uri.parse(base).replace(path: uri.path, query: uri.query, fragment: uri.fragment);
      return fixed.toString();
    }
    return uploadUrl;
  }

  /// Инициализация загрузки (получение presigned URL)
  static Future<UploadInitResponse> initUpload({
    required String fileType, // 'image', 'video', 'audio' or 'document'
    required String contentType, // 'image/jpeg', 'video/mp4', etc.
    required int fileSize,
  }) async {
    var token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated. Please log in first.');
    }
    
    final uri = Uri.parse('$baseUrl/uploads/init');
    var response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'file_type': fileType,
        'content_type': contentType,
        'file_size': fileSize,
      }),
    );
    
    // Если получили 401, пытаемся обновить токен и повторить запрос
    if (response.statusCode == 401) {
      try {
        token = await AuthService.refreshToken();
        response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'file_type': fileType,
            'content_type': contentType,
            'file_size': fileSize,
          }),
        );
      } catch (e) {
        throw Exception('Authentication failed. Please log in again.');
      }
    }
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UploadInitResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(error?['detail'] ?? 'Failed to init upload: ${response.statusCode}');
    }
  }

  /// Загрузка файла по presigned URL
  static Future<void> uploadFile({
    required String uploadUrl,
    required XFile file, // Используем только XFile для кроссплатформенности
    required String contentType,
  }) async {
    // На эмуляторе подменяем localhost на 10.0.2.2
    final effectiveUrl = _fixUploadUrl(uploadUrl);

    // XFile работает на всех платформах (Web, iOS, Android, Desktop)
    final fileBytes = await file.readAsBytes();

    // Если это mock URL (локальная разработка), добавляем токен авторизации
    final headers = <String, String>{
      'Content-Type': contentType,
    };

    // Загрузка через API (не presigned S3) — нужен JWT
    if (effectiveUrl.contains('/uploads/mock/')) {
      final token = await AuthService.getAccessTokenForApi();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await http.put(
      Uri.parse(effectiveUrl),
      headers: headers,
      body: fileBytes,
    );
    
    if (response.statusCode != 200 && response.statusCode != 204) {
      final errorBody = response.body;
      if (errorBody.contains('InvalidAccessKeyId') ||
          errorBody.contains('AWS Access Key')) {
        throw Exception(
          'Хранилище медиа настроено неверно (S3). Обратитесь к администратору или повторите позже.',
        );
      }
      throw Exception('Failed to upload file: ${response.statusCode} - $errorBody');
    }
  }
  
  /// Завершение загрузки
  static Future<UploadCompleteResponse> completeUpload({
    required String uploadId,
    required String fileKey,
    required String fileType,
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/uploads/complete');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'upload_id': uploadId,
        'file_key': fileKey,
        'file_type': fileType,
      }),
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
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/uploads/status/$uploadId');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UploadStatusResponse.fromJson(data);
    } else {
      throw Exception('Failed to get upload status');
    }
  }
  
  /// Полный процесс загрузки (init + upload + complete)
  static Future<UploadCompleteResponse> uploadMediaFile({
    required XFile file, // Используем только XFile для кроссплатформенности
    required String fileType, // 'image', 'video', 'audio' or 'document'
    Function(double)? onProgress,
  }) async {
    try {
      // 1. Определяем content type и размер файла
      // XFile работает на всех платформах
      final filePath = file.path;
      final fileSize = await file.length();
      final contentType = _getContentType(filePath, fileType);
      
      // 2. Инициализация загрузки
      final initResponse = await initUpload(
        fileType: fileType,
        contentType: contentType,
        fileSize: fileSize,
      );
      
      if (onProgress != null) onProgress(0.1);
      
      // 3. Загрузка файла
      await uploadFile(
        uploadUrl: initResponse.uploadUrl,
        file: file,
        contentType: contentType,
      );
      
      if (onProgress != null) onProgress(0.9);
      
      // 4. Завершение загрузки
      final completeResponse = await completeUpload(
        uploadId: initResponse.uploadId,
        fileKey: initResponse.fileKey,
        fileType: fileType,
      );
      
      if (onProgress != null) onProgress(1.0);
      
      if (fileType == 'video' && completeResponse.processing) {
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
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
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
      onProgress?.call(0.9 + progress * 0.1);

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
  
  static String _getContentType(String filePath, String fileType) {
    final extension = filePath.split('.').last.toLowerCase();
    
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
        default:
          return 'audio/mp4';
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
  final String? thumbnailUrl;
  
  UploadStatusResponse({
    required this.status,
    required this.progress,
    this.url,
    this.mp4_720pUrl,
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
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

