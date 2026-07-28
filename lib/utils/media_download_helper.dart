import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/share/system_share.dart';
import '../services/server_config.dart';
import 'api_error_parser.dart';
import 'file_helper.dart';

/// Download / share chat media with Telegram-like actions.
class MediaDownloadHelper {
  static String resolveUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return ServerConfig.resolveMediaUrl(trimmed);
  }

  static String guessFileName(String url, {String fallback = 'haneat_media'}) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    final clean = segment.split('?').first.trim();
    if (clean.isNotEmpty && clean.contains('.')) return clean;
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return '$fallback.png';
    if (lower.contains('.webp')) return '$fallback.webp';
    if (lower.contains('.gif')) return '$fallback.gif';
    if (lower.contains('.mp4')) return '$fallback.mp4';
    if (lower.contains('.mov')) return '$fallback.mov';
    if (lower.contains('.webm')) return '$fallback.webm';
    if (lower.contains('.jpg') || lower.contains('.jpeg')) {
      return '$fallback.jpg';
    }
    return '$fallback.bin';
  }

  static Future<Uint8List> _downloadBytes(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 45),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('download_failed_${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw StateError('download_empty');
    }
    return response.bodyBytes;
  }

  /// Share media as a file (native) or copy/open URL (web).
  static Future<void> shareMedia(
    BuildContext context, {
    required String rawUrl,
    String? subject,
  }) async {
    final url = resolveUrl(rawUrl);
    if (url.isEmpty) return;
    try {
      if (kIsWeb) {
        await SystemShare.shareText(
          context,
          text: url,
          subject: subject,
          webSnackBarText: 'Ссылка скопирована',
        );
        return;
      }
      final bytes = await _downloadBytes(url);
      final name = guessFileName(url);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$name';
      final file = getFileFromPath(path);
      if (file == null) throw StateError('temp_file_unavailable');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(path, name: name)],
        subject: subject ?? name,
        sharePositionOrigin: SystemShare.defaultShareOrigin(context),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось поделиться'),
          ),
        ),
      );
    }
  }

  /// Save/download: open URL on web; native share sheet so user can Save Image.
  static Future<void> saveMedia(
    BuildContext context, {
    required String rawUrl,
  }) async {
    final url = resolveUrl(rawUrl);
    if (url.isEmpty) return;
    try {
      if (kIsWeb) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      final bytes = await _downloadBytes(url);
      final name = guessFileName(url);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$name';
      final file = getFileFromPath(path);
      if (file == null) throw StateError('temp_file_unavailable');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(path, name: name)],
        text: 'Сохранить медиа',
        subject: name,
        sharePositionOrigin: SystemShare.defaultShareOrigin(context),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось сохранить'),
          ),
        ),
      );
    }
  }
}
