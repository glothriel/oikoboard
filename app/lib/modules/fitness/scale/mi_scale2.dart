import 'dart:async';

import 'scale_driver.dart';

const _historyChar = '00002a2f-0000-3512-2118-0009af100700';
const _currentTimeChar = '00002a2b-0000-1000-8000-00805f9b34fb';
const _configChar = '00001542-0000-3512-2118-0009af100700';

// Mi scale user id: fixed, members are picked in the app.
const _userHi = 0;
const _userLo = 0;

const _lbToKg = 0.45359237;

/// Xiaomi Mi (Body Composition) Scale: v2 (service 181B, 13-byte frames with
/// impedance) and v1 (service 181D, 10-byte weight-only records).
class MiScale2Driver extends ScaleDriver {
  MiScale2Driver({
    this.fallbackDelay = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration fallbackDelay;
  final DateTime Function() _now;

  final _out = StreamController<ScaleReading>.broadcast();
  GattIo? _io;
  Timer? _fallback;
  bool _v1 = false;
  bool _onlyLast = false;
  DateTime? _after;
  ScaleReading? _newest; // held back in onlyLast mode
  final _v1Buf = <int>[];

  @override
  String get displayName => 'Xiaomi Mi Scale';

  @override
  LinkMode get linkMode => LinkMode.gatt;

  @override
  Stream<ScaleReading> get readings => _out.stream;

  @override
  bool matches(String name, List<String> serviceUuids) =>
      name.startsWith('MIBFS') ||
      name.startsWith('MIBCS') ||
      name == 'MI SCALE2' ||
      name.startsWith('MI_SCALE');

  @override
  Future<void> onConnected(
    GattIo io, {
    DateTime? after,
    bool onlyLast = false,
  }) async {
    _fallback?.cancel();
    _io = io;
    _after = after;
    _onlyLast = onlyLast;
    _newest = null;
    _v1Buf.clear();
    final services = io.serviceUuids.map(normalizeUuid).toSet();
    _v1 = !services.contains('181b') && services.contains('181d');

    if (!_v1) {
      try {
        await io.write(_configChar, [0x06, 0x04, 0x00, 0x00]); // kg
      } catch (_) {} // best effort
    }
    final t = _now();
    await io.write(_currentTimeChar, [
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
    ]);
    await io.setNotify(_historyChar, true);
    await io.write(_historyChar, [0x01, 0x96, 0x8A, 0xBD, 0x62]);
    await io.write(_historyChar, [0x01, 0xFF, 0xFF, _userHi, _userLo]);
    await io.write(_historyChar, [0x02]);
    if (fallbackDelay > Duration.zero) {
      _fallback = Timer(fallbackDelay, _allRecords);
    }
  }

  Future<void> _allRecords() async {
    final io = _io;
    if (io == null) return;
    await io.write(_historyChar, [0x01, 0x00, 0x00, _userHi, _userLo]);
    await io.write(_historyChar, [0x02]);
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
    if (_v1) {
      if (_v1Buf.isEmpty &&
          ((bytes.length == 1 && bytes[0] == 0x03) ||
              (bytes[0] == 0x01 && bytes.length <= 4))) {
        _control(bytes);
        return;
      }
      _v1Buf.addAll(bytes);
      while (_v1Buf.length >= 10) {
        _emit(_parseV1(_v1Buf.sublist(0, 10)));
        _v1Buf.removeRange(0, 10);
      }
      return;
    }
    if (bytes.length >= 13) {
      for (var i = 0; i + 13 <= bytes.length; i += 13) {
        _emit(_parseV2(bytes.sublist(i, i + 13)));
      }
    } else {
      _control(bytes);
    }
  }

  void _control(List<int> b) {
    if (b.length == 1 && b[0] == 0x03) {
      final io = _io;
      if (io != null) {
        io
            .write(_historyChar, [0x03])
            .then(
              (_) =>
                  io.write(_historyChar, [0x04, 0xFF, 0xFF, _userHi, _userLo]),
            );
      }
      final held = _newest;
      _newest = null;
      if (held != null) _out.add(held);
    } else if (b[0] == 0x01) {
      _fallback?.cancel(); // the count arrived
    }
  }

  void _emit(ScaleReading? r) {
    if (r == null) return;
    final after = _after;
    if (after != null && !_minute(r.time).isAfter(_minute(after))) return;
    if (_onlyLast) {
      // The scale may still send its whole history: keep just the newest.
      final n = _newest;
      if (n == null || r.time.isAfter(n.time)) _newest = r;
      return;
    }
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
  }
}
