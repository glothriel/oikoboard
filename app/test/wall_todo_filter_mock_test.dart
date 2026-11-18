import 'dart:convert';

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
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wall's todo filter: hide lists, show only lists with my tasks or only
/// my tasks; remembered on the device.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('en'),
    ];
  });

  testWidgets('wall todo filter (mock)', (tester) async {
    SharedPreferences.setMockInitialValues({'oiko.wall_layout.mama': 'kanban'});
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

    // Seed: mama has a task on "Dom" and on "Wakacje", none on "Zakupy".
    Future<void> pick(String option) async {
      await tester.tap(find.byTooltip('Filter lists'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(of: find.byType(ListTile), matching: find.text(option))
            .last,
      );
      await tester.pumpAndSettle();
      // Above the sheet (the barrier covers the content, not the nav rail).
      await tester.tapAt(const Offset(800, 100));
      await tester.pumpAndSettle();
    }

    bool shown(String text) => find.text(text).evaluate().isNotEmpty;
    expect(shown('Mleko') && shown('Odkurzyć pokój'), isTrue);

    await pick('Lists with my tasks');
    expect(shown('Mleko'), isFalse); // Zakupy is hidden
    expect(shown('Odkurzyć pokój'), isTrue); // others' tasks on Dom stay
    expect(shown('Zapłacić za prąd'), isTrue);

    await pick('Only my tasks');
    expect(shown('Odkurzyć pokój'), isFalse);
    expect(shown('Zapłacić za prąd') && shown('Zarezerwować nocleg'), isTrue);

    // A task added in this mode is mine, so it stays visible.
    await tester.enterText(
      find.widgetWithText(TextField, 'Add to “Dom”…'),
      'Naprawić kran',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      store
          .list(itemsEntity)
          .singleWhere((i) => i['title'] == 'Naprawić kran')['assignee_id'],
      'mama',
    );
    expect(shown('Naprawić kran'), isTrue);

    // Back to all lists, then switch "Dom" off by hand.
    await pick('All lists');
    expect(shown('Mleko'), isTrue);
    await pick('Dom');
    expect(shown('Odkurzyć pokój'), isFalse);
    expect(shown('Mleko'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('oiko.wall_todo_filter.mama')!);
    expect(saved, {
      'scope': 'all',
      'hidden': ['dom'],
    });
  });
}
