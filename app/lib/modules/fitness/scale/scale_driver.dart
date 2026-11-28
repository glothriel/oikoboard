// Transport-independent scale layer: a driver turns the bytes of one scale
// family into [ScaleReading]s. Nothing outside a driver knows its protocol.

import 'scale_log.dart';

/// The GATT operations a driver needs; the BLE plugin implements it, tests fake it.
abstract interface class GattIo {
  /// Writes [data] to the characteristic [uuid], in [service] when given,
  /// otherwise in any service.
  Future<void> write(String uuid, List<int> data, {String? service});

  /// Enables or disables notifications on the characteristic [uuid] (in
  /// [service] when given).
  Future<void> setNotify(String uuid, bool enabled, {String? service});

  /// The UUID of the service holding the characteristic [uuid]; null when the
  /// device has no such characteristic.
  String? serviceOf(String uuid);

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

/// What a driver tells the session besides readings.
enum ScaleSignal {
  /// The scale sent something: it is still talking.
  activity,

  /// The scale announced the end of its stored history.
  historyComplete,
}

/// The connected device has none of the services the driver can talk to.
class UnsupportedScaleError implements Exception {
  const UnsupportedScaleError(this.message);
  final String message;

  @override
  String toString() => 'UnsupportedScaleError: $message';
}

abstract class ScaleDriver {
  /// Stable identifier of the driver (stored with the paired scale).
  String get id;

  /// Shown to the user for the connected scale.
  String get displayName;

  LinkMode get linkMode;

  /// Whether a device advertising [name] (and [serviceUuids], if advertised)
  /// belongs to this driver.
  bool matches(String name, List<String> serviceUuids);

  /// Runs the connect sequence, logging to [log]. Readings at or before
  /// [after] are dropped. Throws [UnsupportedScaleError] when the device
  /// offers nothing the driver can use.
  Future<void> onConnected(GattIo io, ScaleLog log, {DateTime? after});

  /// Feeds a notification of characteristic [uuid].
  void onNotify(String uuid, List<int> bytes);

  Stream<ScaleReading> get readings;

  /// Activity and end-of-history notices.
  Stream<ScaleSignal> get signals;

  /// Emits a record the driver still holds (the session is ending).
  void flush();

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
