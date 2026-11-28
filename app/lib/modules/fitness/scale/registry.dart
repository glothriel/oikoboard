import 'mi_scale2.dart';
import 'scale_driver.dart';

/// Every supported scale, in priority order; the first match wins. Adding a
/// scale means writing a driver and listing it here.
final List<ScaleDriver> scaleDrivers = [MiScale2Driver()];

/// The driver for a device, or null when none supports it.
ScaleDriver? driverFor(
  String name,
  List<String> serviceUuids, {
  List<ScaleDriver>? drivers,
}) {
  for (final d in drivers ?? scaleDrivers) {
    if (d.matches(name, serviceUuids)) return d;
  }
  return null;
}
