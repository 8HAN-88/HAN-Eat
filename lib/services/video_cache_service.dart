import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'server_config.dart';

/// Скачивает видео в temp-кэш — надёжнее AVPlayer streaming на физическом iOS.
class VideoCacheService {
  static const _minValidBytes = 4096;
  static const _maxParallelPrefetches = 2;
  static final Set<String> _prefetchInFlight = {};

  /// Уже скачанный файл (без сети).
  static Future<File?> cachedFileIfExists(String url) async {
    final resolved = ServerConfig.resolveMediaUrl(url);
    final cacheDir = await _cacheDir();
    final name = md5.convert(resolved.codeUnits).toString();
    final file = File('${cacheDir.path}/$name.mp4');
    if (!await file.exists()) return null;
    final len = await file.length();
    if (len > _minValidBytes) return file;
    await file.delete();
    return null;
  }

  /// Фоновая загрузка для повторного просмотра (не блокирует старт воспроизведения).
  static void prefetchInBackground(String url) {
    final resolved = ServerConfig.resolveMediaUrl(url);
    if (_prefetchInFlight.contains(resolved)) return;
    if (_prefetchInFlight.length >= _maxParallelPrefetches) return;
    _prefetchInFlight.add(resolved);
    unawaited(() async {
      try {
        await fileForUrl(url);
      } catch (e) {
        if (kDebugMode) debugPrint('VideoCache prefetch: $e');
      } finally {
        _prefetchInFlight.remove(resolved);
      }
    }());
  }

  static Future<File> fileForUrl(String url) async {
    final resolved = ServerConfig.resolveMediaUrl(url);
    final cacheDir = await _cacheDir();
    final name = md5.convert(resolved.codeUnits).toString();
    final file = File('${cacheDir.path}/$name.mp4');
    final tempFile = File('${cacheDir.path}/$name.part');

    if (await file.exists()) {
      final len = await file.length();
      if (len > _minValidBytes) return file;
      await file.delete();
    }

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(resolved));
      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('Video HTTP ${response.statusCode} for $resolved');
      }
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (await tempFile.length() < _minValidBytes) {
        await tempFile.delete();
        throw const HttpException('Video file too small');
      }
      await tempFile.rename(file.path);
      if (kDebugMode) {
        debugPrint('VideoCache: saved ${await file.length()} bytes');
      }
      return file;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/haneat_videos');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
