import 'dart:async';

import 'scale_driver.dart';
import 'scale_log.dart';

const _historyChar = '00002a2f-0000-3512-2118-0009af100700';
const _currentTimeChar = '00002a2b-0000-1000-8000-00805f9b34fb';
const _configChar = '00001542-0000-3512-2118-0009af100700';

const _serviceV2 = '181b'; // body composition: 13-byte records
const _serviceV1 = '181d'; // weight scale: 10-byte records

const _lbToKg = 0.45359237;

/// Xiaomi Mi (Body Composition) Scale: v2 (service 181B, 13-byte frames with
/// impedance) and v1 (service 181D, 10-byte weight-only records).
class MiScale2Driver extends ScaleDriver {
  /// [userId] is the 16-bit user id sent in history requests and acks; the
  /// scale echoes it back in its count reply.
  MiScale2Driver({
    this.fallbackDelay = const Duration(seconds: 1),
    this.userId = 0,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration fallbackDelay;
  final int userId;
  final DateTime Function() _now;

  int get _userHi => (userId >> 8) & 0xff;
  int get _userLo => userId & 0xff;

  final _out = StreamController<ScaleReading>.broadcast();
  final _signals = StreamController<ScaleSignal>.broadcast();
  GattIo? _io;
  ScaleLog? _log;
  Timer? _fallback;
  bool _v1 = false;
  String? _service; // the service the history setup worked on
  DateTime? _after;

  /// Bytes of the history stream not yet parsed into records.
  final _buf = <int>[];

  @override
  String get id => 'mi_scale2';

  @override
  String get displayName => 'Xiaomi Mi Scale';

  @override
  LinkMode get linkMode => LinkMode.gatt;

  @override
  Stream<ScaleReading> get readings => _out.stream;

  @override
  Stream<ScaleSignal> get signals => _signals.stream;

  @override
  bool matches(String name, List<String> serviceUuids) =>
      name.startsWith('MIBFS') ||
      name.startsWith('MIBCS') ||
      name == 'MI SCALE2' ||
      name.startsWith('MI_SCALE');

  @override
  Future<void> onConnected(GattIo io, ScaleLog log, {DateTime? after}) async {
    _fallback?.cancel();
    _io = io;
    _log = log;
    _after = after;
    _buf.clear();

    final services = io.serviceUuids.map(normalizeUuid).toSet();
    final holder = io.serviceOf(_historyChar);
    final held = holder == null ? null : normalizeUuid(holder);
    final bool v1;
    if (held == _serviceV1 || held == _serviceV2) {
      v1 = held == _serviceV1;
    } else if (services.contains(_serviceV2)) {
      v1 = false;
    } else if (services.contains(_serviceV1)) {
      v1 = true;
    } else {
      log.warn('no supported service', {'services': services.toList()});
      throw const UnsupportedScaleError('no Mi scale service');
    }
    _v1 = v1;
    log.info('variant', {
      'variant': v1 ? 'v1' : 'v2',
      'historyService': held,
      'services': services.toList(),
    });
    final primary = v1 ? _serviceV1 : _serviceV2;
    final alternate = v1 ? _serviceV2 : _serviceV1;

    if (!v1) {
      try {
        await _write(_configChar, [0x06, 0x04, 0x00, 0x00]); // kg
      } catch (e) {
        log.warn('unit write failed', {'error': '$e'});
      }
    }
    await _writeTime(primary, alternate);
    try {
      await _setupHistory(primary);
      _service = primary;
    } catch (e) {
      log.warn('history setup failed, trying the other service', {
        'service': primary,
        'alternate': alternate,
        'error': '$e',
      });
      await _setupHistory(alternate);
      _service = alternate;
    }
    if (fallbackDelay > Duration.zero) {
      _fallback = Timer(fallbackDelay, _fallbackFired);
    }
  }

  Future<void> _write(String uuid, List<int> data, {String? service}) {
    _log?.debug('write', {
      'char': normalizeUuid(uuid),
      'service': ?service,
      'data': hex(data),
    });
    return _io!.write(uuid, data, service: service);
  }

  /// Best effort: the primary service, the other, then any; never fatal.
  Future<void> _writeTime(String primary, String alternate) async {
    final t = _now();
    final data = [
      t.year & 0xff,
      t.year >> 8,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      0x00,
      0x00,
      0x01,
    ];
    for (final service in [primary, alternate, null]) {
      try {
        await _write(_currentTimeChar, data, service: service);
        return;
      } catch (e) {
        _log?.warn('time write failed', {'service': service, 'error': '$e'});
      }
    }
  }

  Future<void> _setupHistory(String service) async {
    final io = _io!;
    Future<void> subscribe() {
      _log?.debug('subscribe', {'char': normalizeUuid(_historyChar)});
      return io.setNotify(_historyChar, true, service: service);
    }

    // The v1 scale wants history enabled before the subscription.
    if (_v1) {
      await _write(_historyChar, _magic, service: service);
      await subscribe();
    } else {
      await subscribe();
      await _write(_historyChar, _magic, service: service);
    }
    await _write(_historyChar, [
      0x01,
      0xFF,
      0xFF,
      _userHi,
      _userLo,
    ], service: service);
    await _write(_historyChar, [0x02], service: service);
  }

  static const _magic = [0x01, 0x96, 0x8A, 0xBD, 0x62];

  void _fallbackFired() {
    _allRecords().catchError((Object e) {
      _log?.warn('all-records request failed', {'error': '$e'});
    });
  }

  Future<void> _allRecords() async {
    if (_io == null) return;
    _log?.info('requesting all records');
    await _write(_historyChar, [
      0x01,
      0x00,
      0x00,
      _userHi,
      _userLo,
    ], service: _service);
    await _write(_historyChar, [0x02], service: _service);
  }

  /// Runs the "all records" fallback now (what the timer does).
  Future<void> fallbackNow() {
    _fallback?.cancel();
    return _allRecords();
  }

  @override
  void onNotify(String uuid, List<int> bytes) {
    if (normalizeUuid(uuid) != normalizeUuid(_historyChar) || bytes.isEmpty) {
      return;
    }
    _log?.debug('notify', {'data': hex(bytes)});
    _signals.add(ScaleSignal.activity);
    if (_buf.isEmpty) {
      if (bytes.length == 1 && bytes[0] == 0x03) {
        _endOfHistory();
        return;
      }
      if (bytes[0] == 0x01 && bytes.length <= 5) {
        _count(bytes);
        return;
      }
      if (bytes.length == 13 || bytes.length == 26) {
        // Live frames of a weighing in progress (or a whole record batch).
        for (var i = 0; i + 13 <= bytes.length; i += 13) {
          _emit(_parseV2(bytes.sublist(i, i + 13)));
        }
        return;
      }
    }
    _buf.addAll(bytes);
    _drain();
  }

  void _drain() {
    final size = _v1 ? 10 : 13;
    while (_buf.length >= size) {
      final rec = _buf.sublist(0, size);
      _buf.removeRange(0, size);
      _emit(_v1 ? _parseV1(rec) : _parseV2(rec));
    }
  }

  /// `01 count userHi userLo` (8-bit) or `01 lo hi userHi userLo` (16-bit);
  /// anything else starting with `01` is an echo (of the
  /// magic or of a request) and says nothing about the count.
  void _count(List<int> b) {
    final marked =
        b.length >= 4 &&
        b[b.length - 2] == _userHi &&
        b[b.length - 1] == _userLo;
    if (marked && (b.length == 4 || (b.length == 5 && b[1] != 0xFF))) {
      final count = b.length == 4 ? b[1] : b[1] | b[2] << 8;
      _fallback?.cancel(); // the count arrived
      _log?.info('announced count', {'count': count});
      return;
    }
    _log?.debug('ignored echo', {'data': hex(b)});
  }

  void _endOfHistory() {
    _log?.info('end of history');
    _signals.add(ScaleSignal.historyComplete);
    _fallback?.cancel();
    final io = _io;
    if (io == null) return;
    _write(_historyChar, [0x03], service: _service)
        .then(
          (_) => _write(_historyChar, [
            0x04,
            0xFF,
            0xFF,
            _userHi,
            _userLo,
          ], service: _service),
        )
        .catchError((Object e) {
          _log?.warn('ack failed', {'error': '$e'});
        });
  }

  /// Parses whole records left in the buffer; a torn tail is dropped.
  @override
  void flush() {
    _drain();
    if (_buf.isNotEmpty) {
      _log?.warn('dropped partial record', {'data': hex(_buf)});
      _buf.clear();
    }
  }

  void _emit(ScaleReading? r) {
    if (r == null) return;
    final after = _after;
    if (after != null && !_minute(r.time).isAfter(_minute(after))) return;
    _out.add(r);
  }

  static DateTime _minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  static double _kg(int raw, {required bool lb, required bool jin}) {
    if (lb) return raw / 100 * _lbToKg;
    if (jin) return raw / 100 / 2;
    return raw / 200;
  }

  static ScaleReading? _parseV2(List<int> f) {
    final flags = f[1];
    if (flags & 0x20 == 0 || flags & 0x80 != 0) return null;
    final weight = _kg(
      f[11] | f[12] << 8,
      lb: f[0] & 0x01 != 0,
      jin: flags & 0x40 != 0,
    );
    final imp = f[9] | f[10] << 8;
    return ScaleReading(
      time: DateTime(f[2] | f[3] << 8, f[4], f[5], f[6], f[7]),
      weightKg: weight,
      impedance: flags & 0x02 != 0 && imp > 0 ? imp : null,
    );
  }

  static ScaleReading? _parseV1(List<int> r) {
    final s = r[0];
    if (s & 0x20 == 0 || s & 0x80 != 0) return null;
    return ScaleReading(
      time: DateTime(r[3] | r[4] << 8, r[5], r[6], r[7], r[8]),
      weightKg: _kg(r[1] | r[2] << 8, lb: s & 0x01 != 0, jin: s & 0x10 != 0),
    );
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _out.close();
    _signals.close();
  }
}
