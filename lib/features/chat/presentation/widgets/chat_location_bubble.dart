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
  });

  final double latitude;
  final double longitude;
  final String? label;

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
    return ChatLocationPayload(latitude: lat, longitude: lng, label: label);
  }

  static String encode({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    final lines = <String>[
      '📍 Геопозиция',
      'lat: ${latitude.toStringAsFixed(6)}',
      'lng: ${longitude.toStringAsFixed(6)}',
    ];
    final l = label?.trim();
    if (l != null && l.isNotEmpty) lines.add(l);
    return lines.join('\n');
  }
}

class ChatLocationBubble extends StatelessWidget {
  const ChatLocationBubble({
    super.key,
    required this.payload,
    required this.foregroundColor,
    required this.accentColor,
    required this.backgroundColor,
  });

  final ChatLocationPayload payload;
  final Color foregroundColor;
  final Color accentColor;
  final Color backgroundColor;

  Future<void> _openMaps() async {
    final geo = Uri.parse(payload.geoUri);
    if (await canLaunchUrl(geo)) {
      await launchUrl(geo, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse(payload.mapsUrl);
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final coords =
        '${payload.latitude.toStringAsFixed(5)}, ${payload.longitude.toStringAsFixed(5)}';
    final title = payload.label?.trim().isNotEmpty == true
        ? payload.label!.trim()
        : 'Геопозиция';

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                      Icons.location_on_rounded,
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
                    'Открыть в картах',
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
    );
  }
}
