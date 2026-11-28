import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_log.dart';
import '../../../core/backend.dart';
import 'import_cursor.dart';
import 'registry.dart';
import 'scale_driver.dart';
import 'scale_log.dart';

enum ScalePhase { idle, scanning, connected, error, done }

enum ScaleError { bluetoothOff, permissionDenied, notFound, failed }

/// What the weigh-in screen shows about the session.
class ScaleState {
  const ScaleState(this.phase, {this.scaleName, this.error});
  final ScalePhase phase;

  /// The connected scale's `displayName`.
  final String? scaleName;
  final ScaleError? error;
}

/// One weigh-in session: finds a scale, transfers its new readings and
/// remembers (per scale, on this device) which ones were handled.
abstract class ScaleSession {
  Stream<ScaleState> get states;

  /// New readings (after the import cursor of the scale), each once.
  Stream<ScaleReading> get readings;

  /// Starts scanning; failures arrive as an error state, never as an exception.
  Future<void> start();

  /// Marks [reading] handled (saved or discarded): it never comes back.
  Future<void> resolve(ScaleReading reading);

  Future<void> dispose();
}

/// Readings dated further than this from now are scale clock garbage.
const _maxClockSkew = Duration(days: 365 * 20);

/// Whether [t] is within 20 years of [now] (default: the current time).
bool isPlausibleTime(DateTime t, {DateTime? now}) =>
    t.difference(now ?? DateTime.now()).abs() <= _maxClockSkew;

/// Shared state/cursor handling of the sessions.
abstract class _BaseSession implements ScaleSession {
  final _states = StreamController<ScaleState>.broadcast();
  final _readings = StreamController<ScaleReading>.broadcast();
  ImportCursor? _cursor;
  final _seen = <DateTime>{};
  bool _disposed = false;

  @override
  Stream<ScaleState> get states => _states.stream;
  @override
  Stream<ScaleReading> get readings => _readings.stream;

  void emitState(ScaleState s) {
    if (!_disposed) _states.add(s);
  }

  /// Emits [r] when it is new for the scale and not seen in this session.
  void offer(ScaleReading r) {
    final cursor = _cursor;
    if (_disposed || cursor == null || !cursor.isNew(r.time)) return;
    if (!isPlausibleTime(r.time)) return;
    if (_seen.add(r.time)) _readings.add(r);
  }

  @override
  Future<void> resolve(ScaleReading reading) async =>
      _cursor?.advance(reading.time);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _states.close();
    await _readings.close();
  }
}

/// A scale that emits made-up readings; used by the mock backend.
class FakeScaleSession extends _BaseSession {
  FakeScaleSession({List<ScaleReading>? samples, this.delay = Duration.zero})
    : samples = samples ?? defaultSamples();

  final List<ScaleReading> samples;
  final Duration delay;

  static const scaleId = 'fake-scale';

  static List<ScaleReading> defaultSamples() {
    final n = DateTime.now();
    final base = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    return [
      ScaleReading(
        time: base.subtract(const Duration(hours: 2)),
        weightKg: 83.4,
        impedance: 484,
      ),
      ScaleReading(
        time: base.subtract(const Duration(hours: 1)),
        weightKg: 61.0,
        impedance: 548,
      ),
      ScaleReading(
        time: base.subtract(const Duration(minutes: 30)),
        weightKg: 24.8,
      ),
    ];
  }

  @override
  Future<void> start() async {
    emitState(const ScaleState(ScalePhase.scanning));
    _cursor = await ImportCursor.load(scaleId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final name = scaleDrivers.first.displayName;
    emitState(ScaleState(ScalePhase.connected, scaleName: name));
    for (final r in samples) {
      offer(r);
    }
    emitState(ScaleState(ScalePhase.done, scaleName: name));
  }
}

/// The real thing: BLE through `flutter_blue_plus` and the matching driver.
class BleScaleSession extends _BaseSession {
  BleScaleSession(AppLog log) : _log = ScaleLog(log);

  final ScaleLog _log;
  static const _scanTimeout = Duration(seconds: 30);
  static const _idle = Duration(seconds: 12);

  BluetoothDevice? _device;
  ScaleDriver? _driver;
  Timer? _idleTimer;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  Future<void> start() async {
    emitState(const ScaleState(ScalePhase.scanning));
    try {
      if (!await FlutterBluePlus.isSupported) {
        return _fail(ScaleError.failed);
      }
      final adapter = await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 5));
      if (adapter == BluetoothAdapterState.unauthorized) {
        return _fail(ScaleError.permissionDenied);
      }
      if (adapter != BluetoothAdapterState.on) {
        return _fail(ScaleError.bluetoothOff);
      }
      final found = await _scan();
      if (found == null) return _fail(ScaleError.notFound);
      await _connect(found.$1, found.$2);
    } on FlutterBluePlusException catch (e) {
      _fail(_isPermission(e) ? ScaleError.permissionDenied : ScaleError.failed);
    } on TimeoutException {
      _fail(ScaleError.failed);
    } catch (_) {
      _fail(ScaleError.failed);
    }
  }

  static bool _isPermission(FlutterBluePlusException e) =>
      '${e.description}'.toLowerCase().contains('permission');

  void _fail(ScaleError e) {
    _teardown();
    emitState(ScaleState(ScalePhase.error, error: e));
  }

  Future<(BluetoothDevice, ScaleDriver)?> _scan() async {
    final completer = Completer<(BluetoothDevice, ScaleDriver)?>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final driver = driverFor(name, [
          for (final g in r.advertisementData.serviceUuids) g.str,
        ]);
        if (driver != null && !completer.isCompleted) {
          completer.complete((r.device, driver));
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      FlutterBluePlus.isScanning
          .where((s) => !s)
          .first
          .then((_) => completer.isCompleted ? null : completer.complete(null));
      return await completer.future;
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> _connect(BluetoothDevice device, ScaleDriver driver) async {
    _device = device;
    _driver = driver;
    _cursor = await ImportCursor.load(device.remoteId.str);
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
    );
    _subs.add(
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _finish();
      }),
    );
    final services = await device.discoverServices();
    emitState(ScaleState(ScalePhase.connected, scaleName: driver.displayName));
    _subs.add(driver.readings.listen(offer));
    _subs.add(_readings.stream.listen((_) => _bumpIdle()));
    _bumpIdle();
    await driver.onConnected(
      FlutterBlueGattIo(device, services, driver),
      _log,
      after: _cursor!.last,
    );
  }

  void _bumpIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idle, _finish);
  }

  void _finish() {
    if (_disposed || _device == null) return;
    final name = _driver?.displayName;
    _teardown();
    emitState(ScaleState(ScalePhase.done, scaleName: name));
  }

  void _teardown() {
    _idleTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final d = _device;
    _device = null;
    d?.disconnect().catchError((_) {});
  }

  @override
  Future<void> dispose() async {
    _teardown();
    _driver?.dispose();
    _driver = null;
    await super.dispose();
  }
}

/// [GattIo] over a connected `flutter_blue_plus` device.
class FlutterBlueGattIo implements GattIo {
  FlutterBlueGattIo(this._device, this._services, this._driver);
  final BluetoothDevice _device;
  final List<BluetoothService> _services;
  final ScaleDriver _driver;
  final _subscribed = <String>{};

  BluetoothCharacteristic _char(String uuid, [String? service]) {
    final want = normalizeUuid(uuid);
    final inService = service == null ? null : normalizeUuid(service);
    for (final s in _services) {
      if (inService != null && normalizeUuid(s.uuid.str) != inService) continue;
      for (final c in s.characteristics) {
        if (normalizeUuid(c.uuid.str) == want) return c;
      }
    }
    throw StateError('characteristic $uuid not found');
  }

  @override
  List<String> get serviceUuids => [for (final s in _services) s.uuid.str];

  @override
  String? serviceOf(String uuid) {
    final want = normalizeUuid(uuid);
    for (final s in _services) {
      for (final c in s.characteristics) {
        if (normalizeUuid(c.uuid.str) == want) return s.uuid.str;
      }
    }
    return null;
  }

  @override
  Future<void> write(String uuid, List<int> data, {String? service}) =>
      _char(uuid, service).write(data, withoutResponse: false);

  @override
  Future<void> setNotify(String uuid, bool enabled, {String? service}) async {
    final c = _char(uuid, service);
    if (enabled && _subscribed.add(uuid)) {
      _device.cancelWhenDisconnected(
        c.onValueReceived.listen((v) => _driver.onNotify(c.uuid.str, v)),
      );
    }
    await c.setNotifyValue(enabled);
  }
}

/// Makes a session per weigh-in screen visit; null where weighing in is
/// impossible (the real server on web: no Web Bluetooth). The mock backend
/// always gets a [FakeScaleSession], also on web.
final scaleSessionProvider = Provider<ScaleSession Function()?>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend() => FakeScaleSession.new,
    ApiBackend() =>
      kIsWeb ? null : () => BleScaleSession(ref.read(appLogProvider)),
  },
);
