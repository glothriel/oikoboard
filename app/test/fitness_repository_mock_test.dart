import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/modules/fitness/composition.dart';
import 'package:oikoboard/modules/fitness/models.dart';
import 'package:oikoboard/modules/fitness/repository.dart';

Measurement _m(String id, double kg, {int? impedance, double? fat}) =>
    Measurement(
      id: id,
      memberId: 'tata',
      measuredAt: DateTime(2026, 5, 1, 7, 30),
      weightKg: kg,
      impedance: impedance,
      fatPct: fat,
      source: 'scale',
      createdAt: DateTime(2026, 5, 1, 7, 30),
    );

void main() {
  test('JSON round-trips', () {
    final m = _m('a', 80.5, impedance: 500, fat: 20.5);
    final back = Measurement.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
    expect(back.measuredAt, m.measuredAt);
    expect(back.impedance, 500);
    expect(back.hasComposition, isTrue);
    expect(_m('b', 70).copyWith(weightKg: 71).weightKg, 71);
    expect(m.copyWith(fatPct: null).fatPct, isNull);
    expect(m.toBody().containsKey('created_at'), isFalse);

    final p = FitnessProfile(
      id: 'tata',
      sex: Sex.female,
      birthDate: DateTime(1990, 6, 15),
      heightCm: 168.5,
    );
    final pb = FitnessProfile.fromJson(p.toJson());
    expect(pb.toJson(), p.toJson());
    expect(pb.birthDate, DateTime(1990, 6, 15));
    expect(pb.ageOn(DateTime(2026, 6, 14)), 35);
    expect(pb.ageOn(DateTime(2026, 6, 15)), 36);
  });

  test('add and delete a measurement', () async {
    final store = MockStore(latency: Duration.zero);
    final repo = MockFitnessRepository(store, actorId: 'tata');
    final seen = <List<Measurement>>[];
    final sub = repo.watchMeasurements().listen(seen.add);

    await repo.addMeasurement(_m('x', 80));
    await repo.deleteMeasurement(_m('x', 80));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen.map((l) => l.length), [0, 1, 0]);
  });

  test('saving a profile replaces the member\'s own row', () async {
    final store = MockStore(latency: Duration.zero);
    final repo = MockFitnessRepository(store, actorId: 'ola');
    await repo.saveProfile(
      sex: Sex.female,
      birthDate: DateTime(2012, 3, 4),
      heightCm: 150,
    );
    await repo.saveProfile(
      sex: Sex.female,
      birthDate: DateTime(2012, 3, 4),
      heightCm: 152,
    );
    final profiles = await repo.watchProfiles().first;
    expect(profiles, hasLength(1));
    expect(profiles.single.id, 'ola');
    expect(profiles.single.heightCm, 152);
  });

  test('the seed has measurements and a profile', () async {
    final store = MockStore(latency: Duration.zero);
    seedFitnessMock(store);
    final repo = MockFitnessRepository(store, actorId: 'tata');
    final ms = await repo.watchMeasurements().first;
    expect(ms.length, greaterThan(3));
    for (var i = 1; i < ms.length; i++) {
      expect(ms[i - 1].measuredAt.isBefore(ms[i].measuredAt), isFalse);
    }
    expect(await repo.watchProfiles().first, hasLength(1));
  });
}
