import 'package:shared_preferences/shared_preferences.dart';

/// Settings remembered on this device only (not synced): e.g. the calendar
/// view. Failures (no storage) fall back to defaults.
abstract final class DevicePrefs {
  static Future<String?> get(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }
}
