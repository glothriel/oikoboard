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
import 'package:oikoboard/modules/calendar/calendar_screen.dart';
import 'package:oikoboard/modules/calendar/models.dart';
import 'package:oikoboard/modules/calendar/repository.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('event search: a series once, upcoming first', () {
    final now = DateTime.now();
    CalendarEvent ev(String id, String title, int day, {String? series}) {
      final start = DateTime(now.year, now.month, now.day + day, 10);
      return CalendarEvent(
        id: id,
        eventId: series ?? id,
        calendarId: 'c',
        title: title,
        start: start,
        end: start.add(const Duration(hours: 1)),
        allDay: false,
        memberIds: const [],
      );
    }

    final hits = searchEvents([
      ev('a', 'Basen', -7, series: 's'),
      ev('b', 'Basen', 7, series: 's'),
      ev('c', 'Basen', 14, series: 's'),
      ev('d', 'Old basen', -3),
      ev('e', 'Basen trip', 2),
      ev('f', 'Dentist', 1),
    ], ' BASEN ');
    expect(hits.map((e) => e.id), ['e', 'b', 'd']);
  });

  testWidgets('search opens a task in its list (mock)', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('en'),
    ];
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
    tester.view.physicalSize = const Size(1600, 900);
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

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Nothing found'), findsOneWidget);

    await tester.enterText(field, 'paszport');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Wakacje'), findsWidgets);

    await tester.tap(find.text('Paszport dla Oli'));
    await tester.pumpAndSettle();
    // The lists screen with the task's list, and the task's editor.
    expect(find.widgetWithText(TextField, 'Paszport dla Oli'), findsOneWidget);
    expect(find.text('Kupić krem z filtrem'), findsOneWidget);
    Navigator.of(
      tester.element(
        field.evaluate().isEmpty ? find.byType(Scaffold).last : field,
      ),
    ).pop();
    await tester.pumpAndSettle();

    // An event: the calendar on its day, with the event open.
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'urodziny');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urodziny babci'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Urodziny babci'), findsOneWidget);
    final now = DateTime.now();
    final agenda = tester.widget<DayAgenda>(find.byType(DayAgenda));
    expect(agenda.day, DateTime(now.year, now.month, now.day + 3));
  });
}
