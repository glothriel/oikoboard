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
import 'package:oikoboard/modules/registry.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MockStore store;
  late ProviderContainer container;

  Future<void> start(WidgetTester tester) async {
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

    store = MockStore(latency: Duration.zero);
    for (final m in modules) {
      m.seedMock(store);
    }
    container = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(MockBackend(store))],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .set(await MockAuthApi().mockLogin('tata'));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
  }

  TodoItem itemNamed(String title) => store
      .list(itemsEntity)
      .map(TodoItem.fromJson)
      .singleWhere((i) => i.title == title);

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(EditorSheet), matching: f);

  testWidgets('More options is collapsed by default', (tester) async {
    await start(tester);
    await open(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Keep forever'), findsNothing);
    expect(find.text('Description'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Keep forever'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
  });

  testWidgets('starts expanded with a description', (tester) async {
    await start(tester);
    final repo = container.read(todoRepositoryProvider);
    final item = itemNamed('Mleko');
    await tester.runAsync(
      () => repo.updateItem(item, item.copyWith(description: 'two bottles')),
    );
    await open(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    expect(find.text('Keep forever'), findsOneWidget);
    expect(find.text('two bottles'), findsOneWidget);
  });

  testWidgets('starts expanded with Keep forever on', (tester) async {
    await start(tester);
    final repo = container.read(todoRepositoryProvider);
    final item = itemNamed('Mleko');
    await tester.runAsync(
      () => repo.updateItem(item, item.copyWith(keepForever: true)),
    );
    await open(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    expect(find.text('Keep forever'), findsOneWidget);
  });

  testWidgets('Nobody is an icon chip; header order Delete, Comments, Attach', (
    tester,
  ) async {
    await start(tester);
    await open(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    expect(find.text('Assignee'), findsOneWidget);
    expect(find.text('Nobody'), findsNothing);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    expect(find.byTooltip('Nobody'), findsOneWidget);

    final del = tester.getTopLeft(inSheet(find.byTooltip('Delete'))).dx;
    final attach = tester.getTopLeft(inSheet(find.byTooltip('Attach'))).dx;
    expect(inSheet(find.byTooltip('Attach')), findsOneWidget);
    expect(del, lessThan(attach));
    final comments = find.byIcon(Icons.chat_bubble_outline);
    if (comments.evaluate().isNotEmpty) {
      expect(tester.getTopLeft(comments.first).dx, lessThan(attach));
    }
  });

  testWidgets('a change in the section saves', (tester) async {
    await start(tester);
    await open(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More options')); // collapse again
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(itemNamed('Mleko').keepForever, isTrue);
  });

  testWidgets('a new task has the attach button too', (tester) async {
    await start(tester);
    await open(tester);
    await tester.tap(find.byTooltip('New task'));
    await tester.pumpAndSettle();
    expect(inSheet(find.byTooltip('Attach')), findsOneWidget);
    expect(find.text('Attachments'), findsNothing);
  });
}
