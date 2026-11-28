import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_log.dart';
import '../../../core/backend.dart';
import 'import_cursor.dart';
import 'registry.dart';
import 'saved_scale.dart';
import 'scale_driver.dart';
import 'scale_log.dart';

/// [waiting]: connected, the scale has not sent anything yet. [choosing]:
/// several scales were found and none is saved; the user picks one.
enum ScalePhase { idle, scanning, choosing, waiting, connected, error, done }

enum ScaleError {
  bluetoothOff,
  permissionDenied,
  notFound,
  unsupported,
  failed,
}

/// A scale found nearby that the user can pick.
class ScaleCandidate {
  const ScaleCandidate({
    required this.id,
    required this.name,
    required this.driverId,
  });

  /// The BLE device id.
  final String id;
  final String name;
  final String driverId;
}

/// What the weigh-in screen shows about the session.
class ScaleState {
  const ScaleState(
    this.phase, {
    this.scaleName,
    this.error,
    this.candidates = const [],
  });
  final ScalePhase phase;

  /// The scales to pick from while [phase] is [ScalePhase.choosing].
  final List<ScaleCandidate> candidates;

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

  /// Picks [candidate] while [ScalePhase.choosing]; it is saved as the paired
  /// scale.
  Future<void> choose(ScaleCandidate candidate);

  /// Clears the paired scale and ends this session; the caller starts a new
  /// one, which scans again.
  Future<void> forget();

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
  final _choice = Completer<ScaleCandidate?>();

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
  Future<void> choose(ScaleCandidate candidate) async {
    if (!_choice.isCompleted) _choice.complete(candidate);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    if (!_choice.isCompleted) _choice.complete(null);
    await _states.close();
    await _readings.close();
  }
}

/// A scale that emits made-up readings; used by the mock backend.
class FakeScaleSession extends _BaseSession {
  FakeScaleSession({
    List<ScaleReading>? samples,
    this.delay = Duration.zero,
    this.candidates = const [],
  }) : samples = samples ?? defaultSamples();

  final List<ScaleReading> samples;

  /// Scales "in range": with more than one and none saved, the user picks.
  final List<ScaleCandidate> candidates;

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
    final saved = await SavedScale.load();
    var id = saved?.remoteId ?? scaleId;
    var name = saved?.name ?? scaleDrivers.first.displayName;
    if (saved == null && candidates.length > 1) {
      emitState(ScaleState(ScalePhase.choosing, candidates: candidates));
      final picked = await _choice.future;
      if (picked == null || _disposed) return;
      id = picked.id;
      name = picked.name;
      await SavedScale(
        remoteId: id,
        driverId: picked.driverId,
        name: name,
      ).save();
    } else if (saved == null && candidates.length == 1) {
      id = candidates.first.id;
      name = candidates.first.name;
    }
    _cursor = await ImportCursor.load(id);
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
      await SavedScale(
        remoteId: id,
        driverId: scaleDrivers.first.id,
        name: name,
      ).save();
    }
    emitState(ScaleState(ScalePhase.done, scaleName: name));
  }

  @override
  Future<void> forget() async {
    await SavedScale.clear();
    _userDone = true;
    if (!_finish.isCompleted) _finish.complete(false);
    if (!_choice.isCompleted) _choice.complete(null);
  }

  @override
  Future<void> finishNow() async {
    _userDone = true;
    if (!_finish.isCompleted) _finish.complete(false);
  }
}

/// A matching device seen while scanning.
class _Found {
  _Found(this.device, this.driver, this.name);
  final BluetoothDevice device;
  final ScaleDriver driver;
  final String name;

  ScaleCandidate get candidate =>
      ScaleCandidate(id: device.remoteId.str, name: name, driverId: driver.id);
}

/// The real thing: BLE through `flutter_blue_plus` and the matching driver.
class BleScaleSession extends _BaseSession {
  BleScaleSession(AppLog log) : _log = ScaleLog(log);

  final ScaleLog _log;
  static const _scanTimeout = Duration(seconds: 30);

  /// After the first matching device, how long the scan keeps collecting
  /// others so that several scales in range can be offered.
  static const _collectWindow = Duration(seconds: 3);

  /// How long a direct connection to the saved scale may take before the
  /// session falls back to scanning.
  static const _directTimeout = Duration(seconds: 15);

  BluetoothDevice? _device;
  ScaleDriver? _driver;
  ScaleFinisher? _finisher;
  final _subs = <StreamSubscription<Object?>>[];
  bool _aborted = false;

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
      final saved = await SavedScale.load();
      final savedDriver = saved == null ? null : driverById(saved.driverId);
      if (saved != null && savedDriver != null) {
        if (await _connectSaved(saved, savedDriver)) return;
        if (_aborted) return;
      }
      final found = await _scan(
        saved: savedDriver == null ? null : saved,
        driver: savedDriver,
      );
      if (_aborted) return;
      if (found.isEmpty) return _fail(ScaleError.notFound);
      var pick = found.first;
      if (found.length > 1) {
        emitState(
          ScaleState(
            ScalePhase.choosing,
            candidates: [for (final f in found) f.candidate],
          ),
        );
        final choice = await _choice.future;
        if (choice == null || _aborted) return;
        pick = found.firstWhere((f) => f.candidate.id == choice.id);
        _log.info('scale chosen', {'name': pick.name});
        await _saveScale(pick.device, pick.driver, pick.name);
      }
      final services = await _open(pick.device, timeout: _scanTimeoutConnect);
      if (_aborted) return;
      await _run(pick.device, pick.driver, pick.name, services);
    } on FlutterBluePlusException catch (e) {
      _fail(_isPermission(e) ? ScaleError.permissionDenied : ScaleError.failed);
    } on TimeoutException {
      _fail(ScaleError.failed);
    } catch (_) {
      _fail(ScaleError.failed);
    }
  }

  static const _scanTimeoutConnect = Duration(seconds: 20);

  static bool _isPermission(FlutterBluePlusException e) =>
      '${e.description}'.toLowerCase().contains('permission');

  void _fail(ScaleError e) {
    _teardown();
    emitState(ScaleState(ScalePhase.error, error: e));
  }

  Future<void> _saveScale(
    BluetoothDevice device,
    ScaleDriver driver,
    String name,
  ) => SavedScale(
    remoteId: device.remoteId.str,
    driverId: driver.id,
    name: name,
  ).save();

  /// Connects straight to the saved scale; false (cleaned up) when that did
  /// not work and a scan should be tried.
  Future<bool> _connectSaved(SavedScale saved, ScaleDriver driver) async {
    final device = BluetoothDevice.fromId(saved.remoteId);
    _log.info('connecting to saved scale', {'name': saved.name});
    List<BluetoothService> services;
    try {
      services = await _open(
        device,
        timeout: _directTimeout,
        autoConnect: true,
      );
    } on FlutterBluePlusException catch (e) {
      if (_isPermission(e)) rethrow;
      _log.warn('direct connect failed', {'error': '$e'});
      _teardown();
      return false;
    } on TimeoutException {
      _log.warn('direct connect timed out');
      _teardown();
      return false;
    }
    if (_aborted) return true;
    await _run(device, driver, saved.name, services);
    return true;
  }

  /// Scans for scales: only the saved one (by remote id) when [saved] is
  /// given, otherwise every device a driver recognises, collected for a
  /// short window after the first hit.
  Future<List<_Found>> _scan({SavedScale? saved, ScaleDriver? driver}) async {
    final found = <String, _Found>{};
    final completer = Completer<void>();
    Timer? window;
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final id = r.device.remoteId.str;
        final ScaleDriver? d;
        if (saved != null) {
          d = id == saved.remoteId ? driver : null;
        } else {
          d = driverFor(name, [
            for (final g in r.advertisementData.serviceUuids) g.str,
          ]);
        }
        if (d == null || found.containsKey(id)) continue;
        found[id] = _Found(r.device, d, name.isEmpty ? d.displayName : name);
        _log.info('scale found', {'name': name, 'driver': d.id});
        window ??= Timer(
          saved != null ? Duration.zero : _collectWindow,
          () => completer.isCompleted ? null : completer.complete(),
        );
      }
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: _scanTimeout,
        withRemoteIds: saved == null ? const [] : [saved.remoteId],
      );
      FlutterBluePlus.isScanning
          .where((s) => !s)
          .first
          .then((_) => completer.isCompleted ? null : completer.complete());
      await completer.future;
      return found.values.toList();
    } finally {
      window?.cancel();
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  /// Connects to [device] and discovers its services.
  Future<List<BluetoothService>> _open(
    BluetoothDevice device, {
    required Duration timeout,
    bool autoConnect = false,
  }) async {
    _device = device;
    await device.connect(
      license: License.nonprofit,
      timeout: timeout,
      mtu: autoConnect ? null : 512,
      autoConnect: autoConnect,
    );
    _subs.add(
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _finish(FinishReason.disconnect);
        }
      }),
    );
    return device.discoverServices();
  }

  Future<void> _run(
    BluetoothDevice device,
    ScaleDriver driver,
    String scaleName,
    List<BluetoothService> services,
  ) async {
    _driver = driver;
    _cursor = await ImportCursor.load(device.remoteId.str);
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
      await _saveScale(device, driver, scaleName);
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
  Future<void> forget() async {
    _aborted = true;
    await SavedScale.clear();
    _teardown();
    if (!_choice.isCompleted) _choice.complete(null);
  }

  @override
  Future<void> dispose() async {
    _aborted = true;
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
