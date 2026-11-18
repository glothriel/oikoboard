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
    expect(find.text('No comments yet'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Add a comment…'),
      'Lactose-free',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('Lactose-free'), findsOneWidget);
    expect(store.list(commentsEntity).single['item_id'], task()['id']);
    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pumpAndSettle();
    expect(store.list(commentsEntity), isEmpty);
    Navigator.of(tester.element(find.text('No comments yet'))).pop();
    await tester.pumpAndSettle();

    // The board: a column per list; its checkbox ticks the task.
    await tester.tap(find.byTooltip('Board'));
    await tester.pumpAndSettle();
    expect(find.text('Add to “Zakupy”…'), findsOneWidget);
    expect(find.text('Add to “Wakacje”…'), findsOneWidget);
    expect(find.text('Add to “Wakacje”…'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('oiko.wall_layout.mama'), 'kanban');
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
}
