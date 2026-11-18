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
import 'package:oikoboard/core/widgets.dart';
import 'package:oikoboard/modules/calendar/repository.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wall: tapping a task opens it (only the checkbox ticks it), the task
/// has a comment thread, and the board layout is remembered on the device.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('en'),
    ];
  });

  testWidgets('wall tasks, comments and board layout (mock)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
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

    Map<String, dynamic> task() =>
        store.list(itemsEntity).singleWhere((i) => i['title'] == 'Mleko');

    // Tapping the task opens its editor instead of ticking it.
    await tester.ensureVisible(find.text('Mleko'));
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    expect(task()['done'], false);
    // Comments are a separate view, opened from the sheet's bottom bar.
    expect(find.text('Add a comment…'), findsNothing);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Comments: Mleko'), findsOneWidget);
    expect(find.text('No comments yet'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a comment…'),
      'Lactose-free\nplease',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lactose-free'), findsOneWidget);
    expect(store.list(commentsEntity).single['item_id'], task()['id']);
    // Deleting hides it at once with an Undo snackbar; Undo brings it back
    // and nothing reaches the store until the snackbar is gone.
    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lactose-free'), findsNothing);
    expect(find.text('Comment deleted'), findsWidgets);
    expect(store.list(commentsEntity), hasLength(1));
    await tester.tap(find.text('Undo').last); // the sheet's own, on top
    await tester.pumpAndSettle();
    expect(find.textContaining('Lactose-free'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pumpAndSettle(); // shown; its 3 s timer starts now
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Comment deleted'), findsNothing);
    // The mock store finishes the delete partly outside the fake clock.
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(store.list(commentsEntity), isEmpty);
    // Closing the comments view goes back to the task sheet.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Comments'), findsOneWidget);

    // Deleting the task closes the sheet; Undo brings the task back.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Comments'), findsNothing);
    expect(find.text('Mleko'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Mleko'), findsOneWidget);
    expect(
      store.list(itemsEntity).where((i) => i['title'] == 'Mleko'),
      hasLength(1),
    );
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();

    // The checkbox by the title saves the edits, ticks the task and closes the sheet.
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Mleko 2%');
    await tester.tap(find.byTooltip('Mark done'));
    await tester.pumpAndSettle();
    final done = store
        .list(itemsEntity)
        .singleWhere((i) => i['title'] == 'Mleko 2%');
    expect(done['done'], true);
    Map<String, dynamic> task2() =>
        store.list(itemsEntity).singleWhere((i) => i['id'] == done['id']);
    expect(find.byTooltip('Comments'), findsNothing);
    // A snackbar offers Undo, which reopens the task (the edits stay).
    expect(find.text('Done: “Mleko 2%”'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(task2()['done'], false);
    // Without Undo it goes away by itself after 3 s.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Mleko 2%'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(task2()['done'], true);
    expect(find.text('Done: “Mleko 2%”'), findsOneWidget);
    await tester.pumpAndSettle(); // shown; its 3 s timer starts now
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Done: “Mleko 2%”'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Done: “Mleko 2%”'), findsNothing);
    // Back to open for the rest of the test.
    store.patch(itemsEntity, done['id'] as String, {
      'title': 'Mleko',
      'done': false,
      'done_at': null,
    }, actorId: 'mama');
    await tester.pumpAndSettle();

    // The board: a column per list; its checkbox ticks the task.
    await tester.tap(find.byTooltip('Board'));
    await tester.pumpAndSettle();
    expect(find.text('Add to “Zakupy”…'), findsOneWidget);
    expect(find.text('Add to “Wakacje”…'), findsOneWidget);
    expect(find.text('Add to “Wakacje”…'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('oiko.wall_layout.mama'), 'kanban');
    // The + of the add row sits under the checkboxes, its text under the titles.
    final checkbox = tester.getCenter(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Mleko'),
        matching: find.byType(Checkbox),
      ),
    );
    final plus = tester.getCenter(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Add to “Zakupy”…'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(plus.dx, moreOrLessEquals(checkbox.dx, epsilon: 0.5));
    expect(
      tester.getTopLeft(find.text('Add to “Zakupy”…')).dx,
      moreOrLessEquals(tester.getTopLeft(find.text('Mleko')).dx, epsilon: 0.5),
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Mleko'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    expect(task()['done'], true);

    // A list's due date shows in the calendar like a task's.
    final day = DateTime.now().add(const Duration(days: 9));
    final from = DateTime(day.year, day.month, day.day);
    final events = await tester.runAsync(
      () => container.read(calendarRepositoryProvider).watchRange((
        from: from,
        to: from.add(const Duration(days: 1)),
      )).first,
    );
    expect(events!.map((e) => e.title), contains('Lista: Wakacje'));
  });

  testWidgets('task sheet and comments on a phone (mock)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
    tester.view.physicalSize = const Size(390, 800);
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

    // Scroll the task clear of the bottom navigation bar.
    await tester.ensureVisible(find.text('Mleko'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    // The bar with Delete, Comments and Save sits at the bottom, just above
    // the app's navigation bar.
    expect(tester.getBottomLeft(find.text('Save')).dy, greaterThan(650));
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    // Full screen on a phone.
    expect(
      tester.getSize(find.byType(SideSheetScaffold)),
      const Size(390, 800),
    );
    await tester.enterText(find.byType(TextField).last, 'Bez laktozy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
