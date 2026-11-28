import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/mock/mock_auth_api.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/core/session.dart';
import 'package:oikoboard/modules/fitness/composition.dart';
import 'package:oikoboard/modules/fitness/models.dart';
import 'package:oikoboard/modules/fitness/repository.dart';
import 'package:oikoboard/modules/fitness/scale/scale_driver.dart';
import 'package:oikoboard/modules/fitness/scale/scale_session.dart';
import 'package:oikoboard/modules/fitness/weigh_in_screen.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });

  test(
    'measurementFromReading adds composition only with impedance+profile',
    () {
      final reading = ScaleReading(
        time: DateTime(2026, 11, 1, 7, 30),
        weightKg: 80,
        impedance: 500,
      );
      final profile = FitnessProfile(
        id: 'tata',
        sex: Sex.male,
        birthDate: DateTime(1985, 4, 12),
        heightCm: 180,
      );
      final now = DateTime(2026, 11, 1, 8);
      final full = measurementFromReading(
        reading,
        'tata',
        profile,
        id: 'a',
        now: now,
      );
      expect(full.fatPct, isNotNull);
      expect(full.lbmKg, closeTo(80 * (100 - full.fatPct!) / 100, 1e-9));
      expect(full.source, Measurement.sourceScale);
      final noProfile = measurementFromReading(
        reading,
        'tata',
        null,
        id: 'b',
        now: now,
      );
      expect(noProfile.fatPct, isNull);
      expect(noProfile.impedance, 500);
      final noImpedance = measurementFromReading(
        ScaleReading(time: reading.time, weightKg: 80),
        'tata',
        profile,
        id: 'c',
        now: now,
      );
      expect(noImpedance.fatPct, isNull);
    },
  );

  testWidgets('weigh in: suggested member, save, discard, no repeats', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pl');
    Intl.defaultLocale = 'pl';
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MockStore(latency: Duration.zero);
    for (final m in modules) {
      m.seedMock(store);
    }
    final container = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(MockBackend(store))],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .set(await MockAuthApi().mockLogin('tata'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> open() async {
      await tester.tap(find.text('Zważ się'));
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Fitness'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pomiary'));
    await tester.pumpAndSettle();
    await open();

    expect(find.text('Xiaomi Mi Scale', skipOffstage: false), findsNothing);
    expect(find.textContaining('Xiaomi Mi Scale'), findsOneWidget);
    expect(find.text('83.4 kg'), findsOneWidget);
    expect(find.text('61.0 kg'), findsOneWidget);
    expect(find.text('24.8 kg'), findsOneWidget);
    // The suggested members: tata for 83.4, mama for 61.0.
    final first = find.ancestor(
      of: find.text('83.4 kg'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: first, matching: find.text('Tata')),
      findsOneWidget,
    );
    final second = find.ancestor(
      of: find.text('61.0 kg'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: second, matching: find.text('Mama')),
      findsOneWidget,
    );

    // Save the first (tata has a profile → composition), discard the second.
    await tester.tap(find.descendant(of: first, matching: find.text('Zapisz')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: second, matching: find.text('Odrzuć')),
    );
    await tester.pumpAndSettle();
    expect(find.text('83.4 kg'), findsNothing);
    expect(find.text('61.0 kg'), findsNothing);
    final saved = store
        .list(measurementsEntity)
        .where((m) => m['weight_kg'] == 83.4)
        .single;
    expect(saved['member_id'], 'tata');
    expect(saved['source'], 'scale');
    expect(saved['impedance'], 484);
    expect(saved['fat_pct'], isNotNull);
    expect(
      store.list(measurementsEntity).where((m) => m['weight_kg'] == 61.0),
      isEmpty,
    );

    // A second session on the same scale skips both handled readings.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await open();
    expect(find.text('83.4 kg'), findsNothing);
    expect(find.text('61.0 kg'), findsNothing);
    expect(find.text('24.8 kg'), findsOneWidget);
  });

  testWidgets('no readings and the real server on web hides the entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pl');
    Intl.defaultLocale = 'pl';
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MockStore(latency: Duration.zero);
    for (final m in modules) {
      m.seedMock(store);
    }
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(MockBackend(store)),
        scaleSessionProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .set(await MockAuthApi().mockLogin('tata'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Fitness'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pomiary'));
    await tester.pumpAndSettle();
    expect(find.text('Zważ się'), findsNothing);
    expect(find.byTooltip('Dodaj pomiar'), findsOneWidget);
  });
}
