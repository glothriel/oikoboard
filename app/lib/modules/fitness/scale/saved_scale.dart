import 'dart:convert';

import '../../../core/device_prefs.dart';

/// The scale paired with this device: later sessions connect to it directly.
class SavedScale {
  const SavedScale({
    required this.remoteId,
    required this.driverId,
    required this.name,
  });

  /// The BLE device id (MAC address or iOS UUID).
  final String remoteId;
  final String driverId;
  final String name;

  static const _key = 'fitness.scale.paired';

  /// The saved scale, or null when none (or the stored value is unreadable).
  static Future<SavedScale?> load() async {
    final raw = await DevicePrefs.get(_key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final remoteId = j['remoteId'];
      final driverId = j['driverId'];
      if (remoteId is! String || driverId is! String) return null;
      final name = j['name'];
      return SavedScale(
        remoteId: remoteId,
        driverId: driverId,
        name: name is String ? name : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() => DevicePrefs.set(
    _key,
    jsonEncode({'remoteId': remoteId, 'driverId': driverId, 'name': name}),
  );

  static Future<void> clear() => DevicePrefs.remove(_key);
}
