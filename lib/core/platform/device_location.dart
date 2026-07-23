import 'device_location_impl_stub.dart'
    if (dart.library.html) 'device_location_impl_web.dart'
    if (dart.library.io) 'device_location_impl_io.dart' as impl;
import 'device_location_types.dart';

export 'device_location_types.dart';

Future<DeviceLatLng?> getDeviceLocation() => impl.getDeviceLocation();
