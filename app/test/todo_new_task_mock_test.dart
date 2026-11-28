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
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the + button adds a task with the full form (mock)', (
    tester,
  ) async {
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

    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New task'));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsWidgets);
    // A new task can't be ticked, deleted or commented on yet.
    Finder inSheet(Finder f) =>
        find.descendant(of: find.byType(EditorSheet), matching: f);
    expect(inSheet(find.byType(Checkbox)), findsNothing);
    expect(inSheet(find.byTooltip('Delete')), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Task'),
      'Odebrać paczkę',
    );
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    await tester.enterText(inSheet(find.byType(TextField)).last, 'Kod 1234');
    await tester.tap(inSheet(find.text('Mama')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final item = store
        .list(itemsEntity)
        .map(TodoItem.fromJson)
        .singleWhere((i) => i.title == 'Odebrać paczkę');
    expect(item.description, 'Kod 1234');
    expect(item.assigneeId, 'mama');
    expect(item.listId, 'zakupy');
    expect(find.text('Odebrać paczkę'), findsOneWidget);
  });
}
