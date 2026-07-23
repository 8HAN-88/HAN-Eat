// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'device_location_types.dart';

Future<DeviceLatLng?> getDeviceLocation() async {
  final geo = html.window.navigator.geolocation;
  try {
    final pos = await geo.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 12),
    );
    final coords = pos.coords;
    if (coords == null) return null;
    final lat = coords.latitude;
    final lng = coords.longitude;
    if (lat == null || lng == null) return null;
    return DeviceLatLng(latitude: lat.toDouble(), longitude: lng.toDouble());
  } catch (_) {
    return null;
  }
}
