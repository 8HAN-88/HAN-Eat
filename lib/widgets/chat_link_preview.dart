import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/haneat_http_client.dart';
import '../services/auth_service.dart';
import '../services/server_config.dart';

class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: json['url'] as String? ?? '',
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      siteName: json['site_name'] as String?,
    );
  }
}

final RegExp firstHttpUrlPattern = RegExp(
  r'https?://[^\s<>"\]]+',
  caseSensitive: false,
);

String? extractFirstHttpUrl(String text) {
  final match = firstHttpUrlPattern.firstMatch(text.trim());
  if (match == null) return null;
  var url = match.group(0)!;
  while (url.endsWith(')') ||
      url.endsWith(']') ||
      url.endsWith('.') ||
      url.endsWith(',') ||
      url.endsWith('!') ||
      url.endsWith('?')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

class LinkPreviewService {
  static String get _base => ServerConfig.apiBaseUrl;
  static final Map<String, LinkPreview?> _cache = {};
  static final Map<String, Future<LinkPreview?>> _inflight = {};

  static Future<LinkPreview?> fetch(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _fetchUncached(key);
    _inflight[key] = future;
    try {
      final preview = await future;
      _cache[key] = preview;
      return preview;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<LinkPreview?> _fetchUncached(String url) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) return null;
    final uri = Uri.parse('$_base/link-preview').replace(
      queryParameters: {'url': url},
    );
    try {
      final response = await HanEatHttpClient.shared
          .get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      return LinkPreview.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

class ChatLinkPreview extends StatefulWidget {
  const ChatLinkPreview({
    super.key,
    required this.url,
    required this.foregroundColor,
    required this.accentColor,
    required this.backgroundColor,
  });

  final String url;
  final Color foregroundColor;
  final Color accentColor;
  final Color backgroundColor;

  @override
  State<ChatLinkPreview> createState() => _ChatLinkPreviewState();
}

class _ChatLinkPreviewState extends State<ChatLinkPreview> {
  LinkPreview? _preview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  Future<void> _load() async {
    final requested = widget.url.trim();
    setState(() {
      _loading = true;
      _preview = null;
    });
    final preview = await LinkPreviewService.fetch(requested);
    if (!mounted || widget.url.trim() != requested) return;
    setState(() {
      _preview = preview;
      _loading = false;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.foregroundColor.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      );
    }
    final preview = _preview;
    if (preview == null ||
        ((preview.title?.trim().isEmpty ?? true) &&
            (preview.description?.trim().isEmpty ?? true))) {
      return const SizedBox.shrink();
    }

    final imageUrl = preview.imageUrl;
    final resolvedImage = imageUrl != null && imageUrl.isNotEmpty
        ? ServerConfig.resolveMediaUrl(imageUrl)
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openUrl(preview.url),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (resolvedImage != null)
                CachedNetworkImage(
                  imageUrl: resolvedImage,
                  height: 120,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview.siteName?.trim().isNotEmpty ?? false)
                      Text(
                        preview.siteName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (preview.title?.trim().isNotEmpty ?? false) ...[
                      if (preview.siteName?.trim().isNotEmpty ?? false)
                        const SizedBox(height: 2),
                      Text(
                        preview.title!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.foregroundColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (preview.description?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview.description!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.foregroundColor.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
