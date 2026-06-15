import 'package:connectivity_plus/connectivity_plus.dart';

/// Wi‑Fi или Ethernet (не сотовая сеть).
Future<bool> deviceOnWifiOrEthernet() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  } catch (_) {
    return true;
  }
}
