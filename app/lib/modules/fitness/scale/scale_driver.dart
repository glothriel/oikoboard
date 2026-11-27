// Transport-independent scale layer: a driver turns the bytes of one scale
// family into [ScaleReading]s. Nothing outside a driver knows its protocol.

/// The GATT operations a driver needs; the BLE plugin implements it, tests fake it.
abstract interface class GattIo {
  /// Writes [data] to the characteristic [uuid] (found in any service).
  Future<void> write(String uuid, List<int> data);

  /// Enables or disables notifications on the characteristic [uuid].
  Future<void> setNotify(String uuid, bool enabled);

  /// The service UUIDs discovered on the connected device (any UUID form).
  List<String> get serviceUuids;
}

enum LinkMode { gatt, broadcast }

/// One finished weighing. [time] is the scale's local time at minute precision.
class ScaleReading {
  const ScaleReading({
    required this.time,
    required this.weightKg,
    this.impedance,
  });

  final DateTime time;
  final double weightKg;

  /// Ω; null when the scale did not measure it.
  final int? impedance;

  @override
  String toString() => 'ScaleReading($time, $weightKg kg, $impedance Ω)';
}

abstract class ScaleDriver {
  /// Shown to the user for the connected scale.
  String get displayName;

  LinkMode get linkMode;

  /// Whether a device advertising [name] (and [serviceUuids], if advertised)
  /// belongs to this driver.
  bool matches(String name, List<String> serviceUuids);

  /// Runs the connect sequence. Readings at or before [after] are dropped;
  /// with [onlyLast] only the newest stored record is requested (first connect
  /// to a never-seen scale).
  Future<void> onConnected(GattIo io, {DateTime? after, bool onlyLast = false});

  /// Feeds a notification of characteristic [uuid].
  void onNotify(String uuid, List<int> bytes);

  Stream<ScaleReading> get readings;

  /// Releases timers and the stream.
  void dispose();
}

/// Lower-cased UUID, with the Bluetooth base form shortened (`0000181b-0000-1000-8000-00805f9b34fb` → `181b`).
String normalizeUuid(String uuid) {
  final u = uuid.toLowerCase();
  const suffix = '-0000-1000-8000-00805f9b34fb';
  if (u.length == 36 && u.startsWith('0000') && u.endsWith(suffix)) {
    return u.substring(4, 8);
  }
  if (u.length == 8 && u.startsWith('0000')) return u.substring(4);
  return u;
}
