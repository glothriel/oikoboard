import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/modules/fitness/scale/import_cursor.dart';
import 'package:oikoboard/modules/fitness/scale/mi_scale2.dart';
import 'package:oikoboard/modules/fitness/scale/registry.dart';
import 'package:oikoboard/modules/fitness/scale/scale_driver.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hist = '00002a2f-0000-3512-2118-0009af100700';

class FakeIo implements GattIo {
  FakeIo(this.serviceUuids);
  @override
  final List<String> serviceUuids;
  final writes = <(String, List<int>)>[];
  final notify = <String>[];

  @override
  Future<void> write(String uuid, List<int> data) async =>
      writes.add((uuid, data));

  @override
  Future<void> setNotify(String uuid, bool enabled) async => notify.add(uuid);
}

class OtherDriver extends ScaleDriver {
  @override
  String get displayName => 'Other';
  @override
  LinkMode get linkMode => LinkMode.gatt;
  @override
  bool matches(String name, List<String> s) => name == 'OTHER-1';
  @override
  Future<void> onConnected(
    GattIo io, {
    DateTime? after,
    bool onlyLast = false,
  }) async {}
  @override
  void onNotify(String uuid, List<int> bytes) {}
  @override
  Stream<ScaleReading> get readings => const Stream.empty();
  @override
  void dispose() {}
}

List<int> frame({
  int c0 = 0,
  int flags = 0x22,
  int imp = 480,
  int weight = 14000,
  List<int> time = const [2026, 3, 4, 7, 8, 9],
}) => [
  c0,
  flags,
  time[0] & 0xff,
  time[0] >> 8,
  time[1],
  time[2],
  time[3],
  time[4],
  time[5],
  imp & 0xff,
  imp >> 8,
  weight & 0xff,
  weight >> 8,
];

List<int> v1rec(int status, int weight, [int minute = 8]) => [
  status,
  weight & 0xff,
  weight >> 8,
  2026 & 0xff,
  2026 >> 8,
  3,
  4,
  7,
  minute,
  0,
];

Future<(MiScale2Driver, List<ScaleReading>, FakeIo)> connect({
  List<String> services = const ['0000181b-0000-1000-8000-00805f9b34fb'],
  DateTime? after,
  bool onlyLast = false,
  Duration delay = Duration.zero,
}) async {
  final d = MiScale2Driver(
    fallbackDelay: delay,
    now: () => DateTime(2026, 3, 4, 10, 20, 30),
  );
  final got = <ScaleReading>[];
  d.readings.listen(got.add);
  final io = FakeIo(services);
  await d.onConnected(io, after: after, onlyLast: onlyLast);
  return (d, got, io);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('matches names', () {
    final d = MiScale2Driver();
    for (final n in ['MIBFS', 'MIBCS', 'MI SCALE2', 'MI_SCALE123']) {
      expect(d.matches(n, []), isTrue, reason: n);
    }
    for (final n in ['MI SCALE', 'Other', '']) {
      expect(d.matches(n, []), isFalse, reason: n);
    }
  });

  test('registry: first match wins and is open to other drivers', () {
    expect(driverFor('MIBFS', []), isA<MiScale2Driver>());
    expect(driverFor('OTHER-1', []), isNull);
    final other = OtherDriver();
    final list = [other, MiScale2Driver()];
    expect(driverFor('OTHER-1', [], drivers: list), same(other));
    expect(driverFor('MIBFS', [], drivers: list), isA<MiScale2Driver>());
  });

  test('v2 connect writes the six steps in order', () async {
    final (_, _, io) = await connect();
    expect(io.writes.map((w) => w.$2), [
      [6, 4, 0, 0],
      [0xea, 0x07, 3, 4, 10, 20, 30, 0, 0, 1],
      [1, 0x96, 0x8a, 0xbd, 0x62],
      [1, 0xff, 0xff, 0, 0],
      [2],
    ]);
    expect(io.writes[0].$1, '00001542-0000-3512-2118-0009af100700');
    expect(io.writes[1].$1, '00002a2b-0000-1000-8000-00805f9b34fb');
    expect(io.notify, [_hist]);
  });

  test('v1 connect skips the unit write', () async {
    final (_, _, io) = await connect(services: ['181d']);
    expect(io.writes.length, 4);
    expect(io.writes.first.$1, '00002a2b-0000-1000-8000-00805f9b34fb');
  });

  test('falls back to all records without a count, not with one', () async {
    var (d, _, io) = await connect(delay: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(io.writes.map((w) => w.$2).toList().sublist(5), [
      [1, 0, 0, 0, 0],
      [2],
    ]);
    d.dispose();

    (d, _, io) = await connect(delay: const Duration(milliseconds: 20));
    d.onNotify(_hist, [1, 3, 0, 9]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(io.writes.length, 5);
    d.dispose();
  });

  test('03 end of transfer is answered', () async {
    final (d, _, io) = await connect();
    io.writes.clear();
    d.onNotify(_hist, [3]);
    await pump();
    expect(io.writes.map((w) => w.$2), [
      [3],
      [4, 0xff, 0xff, 0, 0],
    ]);
  });

  test('frames parse for kg, lb, jin', () async {
    final (d, got, _) = await connect();
    d.onNotify(_hist, frame());
    d.onNotify(_hist, frame(c0: 1, weight: 15432));
    d.onNotify(_hist, frame(flags: 0x62, weight: 15000));
    await pump();
    expect(got[0].weightKg, 70);
    expect(got[0].impedance, 480);
    expect(got[0].time, DateTime(2026, 3, 4, 7, 8));
    expect(got[1].weightKg, closeTo(154.32 * 0.45359237, 1e-9));
    expect(got[2].weightKg, 75);
  });

  test(
    'drops unstable and removed; impedance only with flag and > 0',
    () async {
      final (d, got, _) = await connect();
      d.onNotify(_hist, frame(flags: 0x02));
      d.onNotify(_hist, frame(flags: 0xa2));
      d.onNotify(_hist, frame(flags: 0x20, imp: 500));
      d.onNotify(_hist, frame(flags: 0x22, imp: 0));
      await pump();
      expect(got.length, 2);
      expect(got[0].impedance, isNull);
      expect(got[1].impedance, isNull);
    },
  );

  test('two frames in a 26-byte notification', () async {
    final (d, got, _) = await connect();
    d.onNotify(_hist, [
      ...frame(weight: 14000),
      ...frame(weight: 15000, time: const [2026, 3, 5, 7, 8, 9]),
    ]);
    await pump();
    expect(got.map((r) => r.weightKg), [70, 75]);
  });

  test('frames at or before the cursor are dropped', () async {
    final (d, got, _) = await connect(after: DateTime(2026, 3, 4, 7, 8));
    d.onNotify(_hist, frame()); // same minute
    d.onNotify(_hist, frame(time: const [2026, 3, 4, 7, 7, 0]));
    d.onNotify(_hist, frame(time: const [2026, 3, 4, 7, 9, 0]));
    await pump();
    expect(got.length, 1);
    expect(got.single.time, DateTime(2026, 3, 4, 7, 9));
  });

  test('onlyLast keeps just the newest record, flushed at 03', () async {
    final (d, got, io) = await connect(onlyLast: true);
    d.onNotify(_hist, frame(time: const [2026, 3, 4, 7, 9, 0], weight: 15000));
    d.onNotify(_hist, frame(time: const [2026, 3, 4, 7, 8, 0]));
    await pump();
    expect(got, isEmpty);
    io.writes.clear();
    d.onNotify(_hist, [3]);
    await pump();
    expect(got.single.weightKg, 75);
    expect(io.writes.map((w) => w.$2), [
      [3],
      [4, 0xff, 0xff, 0, 0],
    ]);
  });

  test('v1 records reassemble from chunks', () async {
    final (d, got, _) = await connect(services: ['181d']);
    final bytes = [
      ...v1rec(0x20, 14000),
      ...v1rec(0x21, 15432, 9),
      ...v1rec(0x30, 15000, 10),
      ...v1rec(0x80 | 0x20, 14000, 11),
      ...v1rec(0x00, 14000, 12),
    ];
    for (var i = 0; i < bytes.length; i += 7) {
      d.onNotify(_hist, bytes.sublist(i, (i + 7).clamp(0, bytes.length)));
    }
    await pump();
    expect(got.length, 3);
    expect(got[0].weightKg, 70);
    expect(got[0].impedance, isNull);
    expect(got[1].weightKg, closeTo(154.32 * 0.45359237, 1e-9));
    expect(got[2].weightKg, 75);
  });

  test('cursor: unknown, advance, persistence, never back', () async {
    SharedPreferences.setMockInitialValues({});
    var c = await ImportCursor.load('AA:BB');
    expect(c.isKnown, isFalse);
    expect(c.isNew(DateTime(2000)), isTrue);
    await c.advance(DateTime(2026, 3, 4, 7, 8, 59));
    expect(c.isNew(DateTime(2026, 3, 4, 7, 8, 30)), isFalse);
    expect(c.isNew(DateTime(2026, 3, 4, 7, 9)), isTrue);
    await c.advance(DateTime(2026, 3, 1));
    c = await ImportCursor.load('AA:BB');
    expect(c.isKnown, isTrue);
    expect(c.last, DateTime(2026, 3, 4, 7, 8));
    expect((await ImportCursor.load('CC')).isKnown, isFalse);
  });
}
