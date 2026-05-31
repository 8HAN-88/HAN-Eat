import 'package:flutter/foundation.dart';
import '../../utils/api_error_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Единая точка для системного «Поделиться»: web — буфер, iOS — [sharePositionOrigin].
class SystemShare {
  static Rect defaultShareOrigin(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

  /// [preShareDelay] — например после закрытия bottom sheet на iOS.
  /// На web: копирует в буфер; при [webSnackBarText] != null показывает SnackBar.
  static Future<void> shareText(
    BuildContext context, {
    required String text,
    String? subject,
    Rect? sharePositionOrigin,
    Duration? preShareDelay,
    String? webSnackBarText,
  }) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (webSnackBarText != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(webSnackBarText)),
        );
      }
      return;
    }
    if (preShareDelay != null) {
      await Future<void>.delayed(preShareDelay);
    }
    if (!context.mounted) return;
    final origin = sharePositionOrigin ?? defaultShareOrigin(context);
    try {
      await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось поделиться'))),
        );
      }
    }
  }
}
