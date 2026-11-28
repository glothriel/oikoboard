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
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The profile form in the mock: a member without a profile sees the hint,
/// an invalid height is rejected, a valid profile saves and the hint goes.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });

  testWidgets('hint, validation and save', (tester) async {
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
    // Ola has no profile in the seed.
    container
        .read(sessionProvider.notifier)
        .set(await MockAuthApi().mockLogin('ola'));
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
    expect(find.text('Uzupełnij profil'), findsOneWidget);

    await tester.tap(find.text('Uzupełnij profil'));
    await tester.pumpAndSettle();
    expect(find.text('Profil fitness'), findsOneWidget);

    // Too short, and no birth date yet.
    await tester.enterText(find.byKey(const Key('fitness-height')), '20');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(find.text('Podaj wzrost od 50 do 250 cm'), findsOneWidget);
    expect(find.text('Wybierz datę urodzenia z przeszłości'), findsOneWidget);
    expect(store.list(profilesEntity).where((p) => p['id'] == 'ola'), isEmpty);

    // Pick the date picker's default (30 years ago) and a valid height.
    await tester.tap(find.byKey(const Key('fitness-birth-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fitness-height')), '165,5');
    await tester.tap(find.text('Kobieta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    final saved = store.list(profilesEntity).where((p) => p['id'] == 'ola');
    expect(saved, hasLength(1));
    expect(saved.single['sex'], 'female');
    expect(saved.single['height_cm'], 165.5);

    // Back on the hub the hint is gone.
    expect(find.text('Uzupełnij profil'), findsNothing);
  });
}
