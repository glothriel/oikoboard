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
import 'package:oikoboard/modules/fitness/repository.dart';
import 'package:oikoboard/modules/fitness/trend_chart.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fitness in the in-memory mock: the nav item, the hub, the measurements
/// list with add and delete, and the wall tile.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });

  testWidgets('wall tile, hub, add and delete a measurement', (tester) async {
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

    // The wall tile shows the signed-in member's latest weight.
    expect(find.text('Waga'), findsOneWidget);
    expect(find.text('83.5'), findsOneWidget);

    // The 4th nav item opens the hub with the Measurements card.
    final nav = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Fitness'),
    );
    await tester.tap(nav);
    await tester.pumpAndSettle();
    expect(find.text('Pomiary'), findsOneWidget);
    expect(find.text('Ostatni: 83.5 kg'), findsOneWidget);

    await tester.tap(find.text('Pomiary'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendChart), findsOneWidget);
    expect(find.text('83.5 kg'), findsOneWidget);
    expect(find.text('61.2 kg'), findsOneWidget); // the household list

    // Add a weight by hand.
    await tester.tap(find.byTooltip('Dodaj pomiar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '82,4');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    final added = store
        .list(measurementsEntity)
        .where((m) => m['weight_kg'] == 82.4)
        .single;
    expect(added['member_id'], 'tata');
    expect(added['source'], 'manual');
    expect(find.text('82.4 kg'), findsOneWidget);

    // Delete it (committed once the Undo snackbar goes away).
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, '82.4 kg'),
        matching: find.byTooltip('Usuń'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('82.4 kg'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      store.list(measurementsEntity).where((m) => m['weight_kg'] == 82.4),
      isEmpty,
    );

    // The back arrow returns to the hub.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Ostatni: 83.5 kg'), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
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
    expect(find.text('Brak wagi'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Fitness'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pomiary'));
    await tester.pumpAndSettle();
    expect(find.text('Brak pomiarów'), findsOneWidget);
  });
}
