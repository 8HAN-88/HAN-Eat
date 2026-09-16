import 'package:shared_preferences/shared_preferences.dart';

import '../features/referral/pending_referral.dart';

class PendingReferralStore {
  PendingReferralStore._();

  static Future<String?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    return PendingReferral.extract(prefs.getString(PendingReferral.prefsKey));
  }

  static Future<void> remember(String? raw) async {
    final code = PendingReferral.extract(raw);
    if (code == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PendingReferral.prefsKey, code);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PendingReferral.prefsKey);
  }

  static Future<String?> officialCode() async {
    final prefs = await SharedPreferences.getInstance();
    return PendingReferral.extract(
      prefs.getString(PendingReferral.officialCodeKey),
    );
  }

  static Future<void> rememberOfficial(String? raw) async {
    final code = PendingReferral.extract(raw);
    if (code == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PendingReferral.officialCodeKey, code);
  }
}
