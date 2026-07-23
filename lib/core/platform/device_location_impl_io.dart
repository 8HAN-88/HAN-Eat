import 'package:geolocator/geolocator.dart';

import 'device_location_types.dart';

/// Native GPS via geolocator (iOS / Android).
Future<DeviceLatLng?> getDeviceLocation() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return DeviceLatLng(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    return null;
  }
}
