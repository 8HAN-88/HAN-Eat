import 'dart:async';

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
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => unawaited(_openMaps()),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.location_on_rounded, color: accentColor),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      payload.label?.trim().isNotEmpty == true
                          ? payload.label!.trim()
                          : 'Геопозиция',
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
      ),
    );
  }
}
