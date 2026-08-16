import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Structured location payload in chat content (or type=location).
class ChatLocationPayload {
  const ChatLocationPayload({
    required this.latitude,
    required this.longitude,
    this.label,
    this.isLive = false,
    this.periodSeconds,
    this.expiresAt,
    this.updatedAt,
    this.stopped = false,
  });

  final double latitude;
  final double longitude;
  final String? label;
  final bool isLive;
  final int? periodSeconds;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final bool stopped;

  bool get isLiveActive {
    if (!isLive || stopped) return false;
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().toUtc().isBefore(exp.toUtc());
  }

  String get mapsUrl =>
      'https://maps.google.com/maps?q=$latitude,$longitude';

  String get geoUri => 'geo:$latitude,$longitude';

  /// OpenStreetMap static preview (no API key).
  String get staticMapUrl {
    final lat = latitude.toStringAsFixed(5);
    final lng = longitude.toStringAsFixed(5);
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lng&zoom=15&size=480x240&maptype=mapnik'
        '&markers=$lat,$lng,red-pushpin';
  }

  static bool _parseBool(String raw) {
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  static DateTime? _parseIso(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static String _fmtIso(DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');

  static ChatLocationPayload? tryParse(String content) {
    final lines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final head = lines.first.toLowerCase();
    final isLoc = head.contains('геопозиц') ||
        head == 'han_location' ||
        head == 'location';
    if (!isLoc) return null;

    double? lat;
    double? lng;
    String? label;
    var isLive = false;
    int? period;
    DateTime? expiresAt;
    DateTime? updatedAt;
    var stopped = false;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (lower.startsWith('lat:') || lower.startsWith('latitude:')) {
        lat = double.tryParse(line.split(':').last.trim());
        continue;
      }
      if (lower.startsWith('lng:') ||
          lower.startsWith('lon:') ||
          lower.startsWith('longitude:')) {
        lng = double.tryParse(line.split(':').last.trim());
        continue;
      }
      if (lower.startsWith('live:')) {
        isLive = _parseBool(line.split(':').last);
        continue;
      }
      if (lower.startsWith('period:')) {
        period = int.tryParse(line.split(':').last.trim());
        continue;
      }
      if (lower.startsWith('expires_at:')) {
        expiresAt = _parseIso(line.substring(line.indexOf(':') + 1));
        continue;
      }
      if (lower.startsWith('updated_at:')) {
        updatedAt = _parseIso(line.substring(line.indexOf(':') + 1));
        continue;
      }
      if (lower.startsWith('stopped:')) {
        stopped = _parseBool(line.split(':').last);
        continue;
      }
      final pair = RegExp(
        r'^(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)$',
      ).firstMatch(line);
      if (pair != null) {
        lat ??= double.tryParse(pair.group(1)!);
        lng ??= double.tryParse(pair.group(2)!);
        continue;
      }
      label ??= line;
    }
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return ChatLocationPayload(
      latitude: lat,
      longitude: lng,
      label: label,
      isLive: isLive,
      periodSeconds: period,
      expiresAt: expiresAt,
      updatedAt: updatedAt,
      stopped: stopped,
    );
  }

  static String encode({
    required double latitude,
    required double longitude,
    String? label,
    bool isLive = false,
    int? periodSeconds,
    DateTime? expiresAt,
    DateTime? updatedAt,
    bool stopped = false,
  }) {
    final lines = <String>[
      '📍 Геопозиция',
      'lat: ${latitude.toStringAsFixed(6)}',
      'lng: ${longitude.toStringAsFixed(6)}',
    ];
    if (isLive) {
      lines.add('live: 1');
      if (periodSeconds != null) lines.add('period: $periodSeconds');
      if (expiresAt != null) lines.add('expires_at: ${_fmtIso(expiresAt)}');
      if (updatedAt != null) lines.add('updated_at: ${_fmtIso(updatedAt)}');
      lines.add('stopped: ${stopped ? 1 : 0}');
    }
    final l = label?.trim();
    if (l != null && l.isNotEmpty) lines.add(l);
    return lines.join('\n');
  }

  /// Instant local stop so the live chip flips before the server answers.
  static String patchStoppedInContent(String content) {
    final payload = tryParse(content);
    if (payload == null || !payload.isLive || payload.stopped) return content;
    return encode(
      latitude: payload.latitude,
      longitude: payload.longitude,
      label: payload.label,
      isLive: true,
      periodSeconds: payload.periodSeconds,
      expiresAt: payload.expiresAt,
      updatedAt: DateTime.now().toUtc(),
      stopped: true,
    );
  }

  String get previewText {
    if (isLiveActive) return '📍 Трансляция геопозиции';
    if (isLive) return '📍 Геопозиция (завершена)';
    return '📍 Геопозиция';
  }
}

class ChatLocationBubble extends StatelessWidget {
  const ChatLocationBubble({
    super.key,
    required this.payload,
    required this.foregroundColor,
    required this.accentColor,
    required this.backgroundColor,
    this.isMine = false,
    this.onStopLive,
  });

  final ChatLocationPayload payload;
  final Color foregroundColor;
  final Color accentColor;
  final Color backgroundColor;
  final bool isMine;
  final VoidCallback? onStopLive;

  Future<void> _openMaps() async {
    final geo = Uri.parse(payload.geoUri);
    if (await canLaunchUrl(geo)) {
      await launchUrl(geo, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse(payload.mapsUrl);
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  String _statusLine() {
    if (!payload.isLive) return 'Открыть в картах';
    if (payload.isLiveActive) {
      final exp = payload.expiresAt?.toLocal();
      if (exp == null) return 'Трансляция';
      final left = exp.difference(DateTime.now());
      if (left.isNegative) return 'Трансляция завершена';
      final mins = left.inMinutes;
      if (mins >= 60) {
        final h = mins ~/ 60;
        final m = mins % 60;
        return 'Трансляция · ещё $hч $mм';
      }
      return 'Трансляция · ещё $mins мин';
    }
    return 'Трансляция завершена';
  }

  @override
  Widget build(BuildContext context) {
    final coords =
        '${payload.latitude.toStringAsFixed(5)}, ${payload.longitude.toStringAsFixed(5)}';
    final title = payload.isLive
        ? (payload.isLiveActive ? 'Трансляция геопозиции' : 'Геопозиция')
        : (payload.label?.trim().isNotEmpty == true
            ? payload.label!.trim()
            : 'Геопозиция');

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => unawaited(_openMaps()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 120,
                  width: 240,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: payload.staticMapUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 180),
                        placeholder: (_, __) => ColoredBox(
                          color: accentColor.withValues(alpha: 0.12),
                          child: Center(
                            child: Icon(
                              Icons.map_outlined,
                              color: accentColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: accentColor.withValues(alpha: 0.12),
                          child: Center(
                            child: Icon(
                              Icons.location_on_rounded,
                              color: accentColor,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Icon(
                          payload.isLiveActive
                              ? Icons.my_location_rounded
                              : Icons.location_on_rounded,
                          color: accentColor,
                          size: 34,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      if (payload.isLiveActive)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        coords,
                        style: TextStyle(
                          color: foregroundColor.withValues(alpha: 0.7),
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLine(),
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMine && payload.isLiveActive && onStopLive != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: OutlinedButton(
                onPressed: onStopLive,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Остановить'),
              ),
            ),
        ],
      ),
    );
  }
}
