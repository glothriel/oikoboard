import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import '../../core/sync/outbox.dart';
import 'composition.dart';
import 'models.dart';

const measurementsEntity = 'measurements';
const profilesEntity = 'fitness_profiles';

/// The interface the UI uses. The `watch*` methods match the server's views
/// (fitness.measurements, fitness.profiles).
abstract interface class FitnessRepository {
  /// All household members' measurements, newest first.
  Stream<List<Measurement>> watchMeasurements();

  /// The members' profiles (one per member, the id is the member id).
  Stream<List<FitnessProfile>> watchProfiles();

  Future<void> addMeasurement(Measurement measurement);
  Future<void> deleteMeasurement(Measurement measurement);

  /// Creates or replaces the signed-in member's own profile.
  Future<void> saveProfile({
    required Sex sex,
    required DateTime birthDate,
    required double heightCm,
  });
}

List<Measurement> _sortMeasurements(Iterable<Measurement> m) =>
    m.toList()..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

// --- API ---

class ApiFitnessRepository implements FitnessRepository {
  ApiFitnessRepository(
    this.api,
    this.sync,
    this.outbox, {
    required this.actorId,
  });
  final ApiClient api;
  final SyncClient sync;
  final Outbox outbox;
  final String actorId;

  @override
  Stream<List<Measurement>> watchMeasurements() => sync
      .watch(
        'fitness.measurements',
        const {},
        (e, _) => e == measurementsEntity,
      )
      .map(
        (v) => _sortMeasurements(
          v.rows(measurementsEntity).map(Measurement.fromJson),
        ),
      );

  @override
  Stream<List<FitnessProfile>> watchProfiles() => sync
      .watch('fitness.profiles', const {}, (e, _) => e == profilesEntity)
      .map((v) => v.rows(profilesEntity).map(FitnessProfile.fromJson).toList());

  @override
  Future<void> addMeasurement(Measurement m) async => outbox.enqueue(
    Mutation.create(
      '/fitness/measurements',
      measurementsEntity,
      m.toJson(),
      body: m.toBody(),
      label: '${m.weightKg} kg',
    ),
  );

  @override
  Future<void> deleteMeasurement(Measurement m) async => outbox.enqueue(
    Mutation.delete(
      '/fitness/measurements/${m.id}',
      measurementsEntity,
      m.id,
      label: '${m.weightKg} kg',
    ),
  );

  @override
  Future<void> saveProfile({
    required Sex sex,
    required DateTime birthDate,
    required double heightCm,
  }) async {
    final p = FitnessProfile(
      id: actorId,
      sex: sex,
      birthDate: birthDate,
      heightCm: heightCm,
    );
    // The server upserts by member; a create overwrites the row in the views.
    outbox.enqueue(
      Mutation.create(
        '/fitness/profiles',
        profilesEntity,
        p.toJson(),
        body: {
          'sex': sex.name,
          'birth_date': toApiDate(birthDate),
          'height_cm': heightCm,
        },
        label: 'profile',
      ),
    );
  }
}

// --- mock ---

class MockFitnessRepository implements FitnessRepository {
  MockFitnessRepository(this.store, {required this.actorId});
  final MockStore store;
  final String actorId;

  @override
  Stream<List<Measurement>> watchMeasurements() => store
      .watch(measurementsEntity)
      .map((docs) => _sortMeasurements(docs.map(Measurement.fromJson)));

  @override
  Stream<List<FitnessProfile>> watchProfiles() => store
      .watch(profilesEntity)
      .map((docs) => docs.map(FitnessProfile.fromJson).toList());

  @override
  Future<void> addMeasurement(Measurement m) async {
    await store.put(measurementsEntity, m.toJson(), actorId: actorId);
  }

  @override
  Future<void> deleteMeasurement(Measurement m) =>
      store.delete(measurementsEntity, m.id, actorId: actorId);

  @override
  Future<void> saveProfile({
    required Sex sex,
    required DateTime birthDate,
    required double heightCm,
  }) async {
    await store.put(
      profilesEntity,
      FitnessProfile(
        id: actorId,
        sex: sex,
        birthDate: birthDate,
        heightCm: heightCm,
      ).toJson(),
      actorId: actorId,
    );
  }
}

/// Made-up sample data for the mock backend (called from the fitness module's
/// `seedMock`): a few weigh-ins of two members and one profile.
void seedFitnessMock(MockStore store) {
  final now = DateTime.now();
  var n = 0;
  void weigh(
    String member,
    int daysAgo,
    double kg, {
    int? impedance,
    double? fat,
  }) {
    final at = DateTime(now.year, now.month, now.day - daysAgo, 7, 30);
    store.seed(
      measurementsEntity,
      Measurement(
        id: 'seed-meas-${n++}',
        memberId: member,
        measuredAt: at,
        weightKg: kg,
        impedance: impedance,
        fatPct: fat,
        lbmKg: fat == null ? null : kg * (100 - fat) / 100,
        bmi: fat == null ? null : kg / (1.8 * 1.8),
        source: impedance == null
            ? Measurement.sourceManual
            : Measurement.sourceScale,
        createdAt: at,
      ).toJson(),
    );
  }

  weigh('tata', 21, 84.6, impedance: 492, fat: 21.4);
  weigh('tata', 14, 84.1, impedance: 488, fat: 21.1);
  weigh('tata', 7, 83.8, impedance: 485, fat: 20.9);
  weigh('tata', 1, 83.5, impedance: 483, fat: 20.7);
  weigh('mama', 10, 61.2, impedance: 551);
  weigh('mama', 3, 60.9);
  store.seed(
    profilesEntity,
    FitnessProfile(
      id: 'tata',
      sex: Sex.male,
      birthDate: DateTime(1985, 4, 12),
      heightCm: 180,
    ).toJson(),
  );
}

// --- providers ---

final fitnessRepositoryProvider = Provider<FitnessRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => MockFitnessRepository(
      store,
      actorId: ref.watch(currentMemberProvider),
    ),
    ApiBackend() => ApiFitnessRepository(
      ref.watch(apiClientProvider),
      ref.watch(syncClientProvider),
      ref.watch(outboxProvider)!,
      actorId: ref.watch(currentMemberProvider),
    ),
  },
);

final measurementsProvider = StreamProvider<List<Measurement>>(
  (ref) => ref.watch(fitnessRepositoryProvider).watchMeasurements(),
);

final fitnessProfilesProvider = StreamProvider<List<FitnessProfile>>(
  (ref) => ref.watch(fitnessRepositoryProvider).watchProfiles(),
);
