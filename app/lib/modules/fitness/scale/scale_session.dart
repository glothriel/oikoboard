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

/// [waiting]: connected, the scale has not sent anything yet.
enum ScalePhase { idle, scanning, waiting, connected, error, done }

enum ScaleError {
  bluetoothOff,
  permissionDenied,
  notFound,
  unsupported,
  failed,
}

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

  /// The user is done: ends the session now (readings held by the driver are
  /// flushed first).
  Future<void> finishNow();

  Future<void> dispose();
}

/// Why a session ended; logged.
enum FinishReason { idle, disconnect, user, history }

/// No driver signal for this long ends the session.
const scaleSilenceTimeout = Duration(seconds: 60);

/// Quiet period after the end-of-history notice that ends the session.
const scaleQuietPeriod = Duration(seconds: 2);

/// The session's timing rules, free of BLE so tests can drive them: any
/// signal resets the silence timer, end-of-history plus a quiet period (or
/// silence, the user, a disconnect) finishes once and flushes the driver.
class ScaleFinisher {
  ScaleFinisher({
    required Stream<ScaleSignal> signals,
    required this.flush,
    required this.onFinish,
    this.onActivity,
    this.silence = scaleSilenceTimeout,
    this.quiet = scaleQuietPeriod,
  }) {
    _sub = signals.listen(_onSignal);
    _silenceTimer = Timer(silence, () => finish(FinishReason.idle));
  }

  final void Function() flush;
  final void Function(FinishReason) onFinish;

  /// Called on every signal (e.g. to leave the waiting state).
  final void Function()? onActivity;
  final Duration silence;
  final Duration quiet;

  late final StreamSubscription<ScaleSignal> _sub;
  Timer? _silenceTimer;
  Timer? _quietTimer;
  bool _historyDone = false;
  bool _finished = false;

  bool get finished => _finished;

  void _onSignal(ScaleSignal s) {
    if (_finished) return;
    onActivity?.call();
    if (s == ScaleSignal.historyComplete) _historyDone = true;
    bump();
  }

  /// Something happened (a signal, an emitted reading): restart the timer.
  void bump() {
    if (_finished) return;
    _silenceTimer?.cancel();
    _quietTimer?.cancel();
    if (_historyDone) {
      _quietTimer = Timer(quiet, () => finish(FinishReason.history));
    } else {
      _silenceTimer = Timer(silence, () => finish(FinishReason.idle));
    }
  }

  void finish(FinishReason reason) {
    if (_finished) return;
    _finished = true;
    _silenceTimer?.cancel();
    _quietTimer?.cancel();
    _sub.cancel();
    flush();
    onFinish(reason);
  }

  void cancel() {
    _finished = true;
    _silenceTimer?.cancel();
    _quietTimer?.cancel();
    _sub.cancel();
  }
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

  /// How long the session waits for the "scale" before it sends [samples];
  /// [finishNow] ends the wait early.
  final Duration delay;
  final _finish = Completer<bool>();
  bool _userDone = false;

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
    final name = scaleDrivers.first.displayName;
    emitState(ScaleState(ScalePhase.waiting, scaleName: name));
    if (delay > Duration.zero) {
      final timer = Timer(delay, () {
        if (!_finish.isCompleted) _finish.complete(true);
      });
      await _finish.future;
      timer.cancel();
    }
    if (!_userDone && !_disposed) {
      emitState(ScaleState(ScalePhase.connected, scaleName: name));
      for (final r in samples) {
        offer(r);
      }
    }
    emitState(ScaleState(ScalePhase.done, scaleName: name));
  }

  @override
  Future<void> finishNow() async {
    _userDone = true;
    if (!_finish.isCompleted) _finish.complete(false);
  }
}

/// The real thing: BLE through `flutter_blue_plus` and the matching driver.
class BleScaleSession extends _BaseSession {
  BleScaleSession(AppLog log) : _log = ScaleLog(log);

  final ScaleLog _log;
  static const _scanTimeout = Duration(seconds: 30);

  BluetoothDevice? _device;
  ScaleDriver? _driver;
  ScaleFinisher? _finisher;
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
        if (s == BluetoothConnectionState.disconnected) {
          _finish(FinishReason.disconnect);
        }
      }),
    );
    final services = await device.discoverServices();
    final name = driver.displayName;
    emitState(ScaleState(ScalePhase.waiting, scaleName: name));
    _subs.add(driver.readings.listen(offer));
    final finisher = _finisher = ScaleFinisher(
      signals: driver.signals,
      flush: driver.flush,
      onActivity: () =>
          emitState(ScaleState(ScalePhase.connected, scaleName: name)),
      onFinish: _finished,
    );
    _subs.add(_readings.stream.listen((_) => finisher.bump()));
    try {
      await driver.onConnected(
        FlutterBlueGattIo(device, services, driver),
        _log,
        after: _cursor!.last,
      );
    } on UnsupportedScaleError catch (e) {
      _log.warn('unsupported scale', {'reason': e.message});
      _fail(ScaleError.unsupported);
    }
  }

  void _finish(FinishReason reason) => _finisher?.finish(reason);

  @override
  Future<void> finishNow() async => _finish(FinishReason.user);

  Future<void> _finished(FinishReason reason) async {
    if (_disposed || _device == null) return;
    _log.info('session ended', {'reason': reason.name});
    final name = _driver?.displayName;
    // Let readings flushed by the driver reach their listeners first.
    await Future<void>.delayed(Duration.zero);
    _teardown();
    emitState(ScaleState(ScalePhase.done, scaleName: name));
  }

  void _teardown() {
    _finisher?.cancel();
    _finisher = null;
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
