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
import 'package:oikoboard/modules/registry.dart';
import 'package:oikoboard/modules/todo/recurring.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MockStore> _open(WidgetTester tester) async {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localesTestValue = const [
    Locale('en'),
  ];
  SharedPreferences.setMockInitialValues({});
  await initializeDateFormatting('en');
  Intl.defaultLocale = 'en';
  tester.view.physicalSize = const Size(1600, 1200);
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
  await tester.tap(find.byIcon(Icons.checklist_outlined));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('create, pause and delete a recurring task (mock)', (
    tester,
  ) async {
    final store = await _open(tester);

    await tester.tap(find.byTooltip('Recurring tasks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No recurring tasks yet'), findsOneWidget);

    await tester.tap(find.byTooltip('New recurring task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Książki');
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last day of the month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After some days'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Days after creation'),
      '3',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // the preview lists the next occurrences and the first due date
    expect(find.text('Next occurrences', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('The first task will be due', skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final t = store.list(recurringEntity).map(RecurringTask.fromJson).single;
    expect(t.title, 'Książki');
    expect(t.rrule, 'FREQ=MONTHLY;BYMONTHDAY=-1');
    expect(t.listId, 'zakupy');
    expect(t.dueOffsetDays, 3);
    expect(t.active, isTrue);
    expect(find.text('Książki'), findsOneWidget);
    expect(find.text('Every month on the last day'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      store.list(recurringEntity).map(RecurringTask.fromJson).single.active,
      isFalse,
    );
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.text('Książki'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.list(recurringEntity), isEmpty);
  });

  testWidgets('weekday chips build the weekly rule (mock)', (tester) async {
    final store = await _open(tester);
    await tester.tap(find.byTooltip('Recurring tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New recurring task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Zakupy');
    // Weekly is the default; pick exactly Monday and Friday.
    for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      final chip = find.widgetWithText(FilterChip, d);
      final selected = tester.widget<FilterChip>(chip).selected;
      if (selected != (d == 'Mon' || d == 'Fri')) {
        await tester.tap(chip);
        await tester.pump();
      }
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      store.list(recurringEntity).map(RecurringTask.fromJson).single.rrule,
      'FREQ=WEEKLY;BYDAY=MO,FR',
    );
    expect(find.text('Every week on Mon, Fri'), findsOneWidget);
  });
}
