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
import 'package:oikoboard/modules/calendar/models.dart';
import 'package:oikoboard/modules/calendar/repository.dart';
import 'package:oikoboard/modules/calendar/time_grid.dart';
import 'package:oikoboard/modules/registry.dart';

/// The calendar works in the in-memory mock: linked calendars, adding an
/// event through the editor (with a calendar and repeat choice).
void main() {
  testWidgets('calendar screen and editor in mock mode', (tester) async {
    await initializeDateFormatting('pl');
    Intl.defaultLocale = 'pl';
    // Known, unrelated: no Cupertino localizations for `pl` (app.dart).
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(1400, 1000);
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
        .set(await MockAuthApi().mockLogin('mama'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalendarz').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Kalendarze'), findsOneWidget);
    await tester.tap(find.byTooltip('Nowe wydarzenie'));
    await tester.pumpAndSettle();
    expect(find.text('Kalendarz'), findsWidgets);
    expect(find.text('Powtarzanie'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tytuł'), 'Joga');
    await tester.tap(find.text('Nie powtarza się'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Co tydzień').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    final added = store
        .list(eventsEntity)
        .where((e) => e['title'] == 'Joga')
        .single;
    expect(added['calendar_id'], 'cal-family');
    expect(added['recurrence'], ['RRULE:FREQ=WEEKLY']);

    // The calendars sheet lists the linked calendars.
    await tester.tap(find.byTooltip('Kalendarze'));
    await tester.pumpAndSettle();
    expect(find.text('Szkoła'), findsOneWidget);
  });

  testWidgets('views switch, fit the phone and are remembered', (tester) async {
    await initializeDateFormatting('pl');
    Intl.defaultLocale = 'pl';
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(400, 800);
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
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Kalendarz'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimeGrid), findsNothing); // month by default

    Future<void> pick(String label) async {
      await tester.tap(find.byTooltip('Widok'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    // 3 days fit the width; the week scrolls sideways.
    await pick('3 dni');
    expect(find.byType(TimeGrid), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TimeGrid),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    await pick('Tydzień');
    expect(
      find.descendant(
        of: find.byType(TimeGrid),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNWidgets(2), // day headers + grid
    );
    await tester.tap(find.byTooltip('Następny okres'));
    await tester.pumpAndSettle();

    expect(
      await container.read(calendarRepositoryProvider).preferredView(),
      CalendarView.week,
    );
  });
}
