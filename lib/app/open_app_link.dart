import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_router.dart';

/// Свои ссылки (`haneat.app/reel/28`, `/post/…`) открываем в приложении.
/// Чужие — во внешнем браузере.
Future<bool> openAppOrExternalLink(BuildContext context, String raw) async {
  final path = parseDeepLinkToGoPath(raw.trim());
  if (path != null && path.isNotEmpty) {
    context.push(path);
    return true;
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !(uri.hasScheme && uri.host.isNotEmpty)) {
    return false;
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
